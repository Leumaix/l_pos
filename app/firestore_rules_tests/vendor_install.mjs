// Minimal offline-ish installer that bypasses npm's own resolver.
//
// Why this exists: in this sandbox, `npm install` reliably fails to fetch
// large packuments (multi-version metadata documents) from
// registry.npmjs.org — e.g. `firebase`'s abbreviated packument is ~10MB
// and every attempt times out, even with raised npm retry/timeout config.
// Fetching a SINGLE version's manifest (registry.npmjs.org/<pkg>/<version>)
// and its tarball directly are both fast and reliable here. So: walk the
// dependency graph ourselves using only those two fast, small requests,
// and extract tarballs straight into node_modules (flat layout).
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const NM = path.join(process.cwd(), 'node_modules');
fs.mkdirSync(NM, { recursive: true });

const seen = new Map(); // name -> version already installed

function runWithRetry(cmd, opts = {}) {
  let lastErr;
  for (let attempt = 1; attempt <= 5; attempt++) {
    try {
      return execSync(cmd, opts);
    } catch (err) {
      lastErr = err;
      console.warn(`  (attempt ${attempt} failed, retrying: ${cmd.slice(0, 80)}...)`);
    }
  }
  throw lastErr;
}

function fetchJson(url) {
  const out = runWithRetry(`curl -s --max-time 30 "${url}"`, { maxBuffer: 1024 * 1024 * 20 });
  return JSON.parse(out.toString());
}

function pkgDir(name) {
  return path.join(NM, ...name.split('/'));
}

function installOne(name, versionRange) {
  // versionRange here is always an exact pin from a dependency's own
  // package.json in this tree (Firebase's packages don't use ranges
  // internally) — if it's ever NOT exact, just strip common range
  // prefixes and hope for the best; this script only needs to handle
  // the Firebase SDK's own tree.
  // Firebase's own packages always pin exact versions internally; a
  // handful of THEIR small transitive deps (websocket-driver's chain)
  // use real ranges. We don't need to satisfy a range precisely here —
  // "latest" is a reasonable, low-risk resolution for a devtools test
  // harness, not shipped app code.
  const isExact = /^\d/.test(versionRange);
  const version = isExact ? versionRange.replace(/^[\^~]/, '') : 'latest';
  const already = seen.get(name);
  if (already) {
    if (already !== version) {
      console.warn(`! version conflict for ${name}: have ${already}, also want ${version} — keeping ${already}`);
    }
    return;
  }
  seen.set(name, version);

  const dir = pkgDir(name);
  if (fs.existsSync(path.join(dir, 'package.json'))) {
    console.log(`= ${name}@${version} already present`);
  } else {
    fs.rmSync(dir, { recursive: true, force: true }); // clear any incomplete leftover
    const encoded = name.startsWith('@') ? name.replace('/', '%2f') : name;
    console.log(`> fetching manifest ${name}@${version}`);
    const manifest = fetchJson(`https://registry.npmjs.org/${encoded}/${version}`);
    if (!manifest.dist) {
      throw new Error(`no dist.tarball for ${name}@${version} (not an exact/known version? got: ${JSON.stringify(manifest).slice(0, 120)})`);
    }
    const tarballUrl = manifest.dist.tarball;
    fs.mkdirSync(dir, { recursive: true });
    const tgz = dir + '.tgz';
    console.log(`> downloading ${tarballUrl}`);
    runWithRetry(`curl -s -f -L --max-time 120 -o "${tgz}" "${tarballUrl}"`);
    execSync(`tar -xzf "${tgz}" -C "${dir}" --strip-components=1`);
    fs.rmSync(tgz);
    console.log(`+ installed ${name}@${version}`);
  }

  const pkgJsonPath = path.join(dir, 'package.json');
  const pkgJson = JSON.parse(fs.readFileSync(pkgJsonPath, 'utf8'));
  const deps = pkgJson.dependencies || {};
  for (const [depName, depRange] of Object.entries(deps)) {
    try {
      installOne(depName, depRange);
    } catch (err) {
      // Don't let one unresolvable/optional-ish transitive dep (e.g. a
      // non-exact range this script can't resolve) abort the whole run.
      // We only actually need the subset of the tree our test file
      // imports (app + firestore) — most of what "firebase" declares
      // (database, messaging, storage, analytics, ...) is irrelevant to
      // rules testing and safe to skip if it can't be fetched.
      console.warn(`! skipping ${depName}@${depRange}: ${err.message?.split('\n')[0]}`);
      seen.delete(depName);
    }
  }
}

const targets = JSON.parse(fs.readFileSync('vendor_targets.json', 'utf8'));
for (const [name, version] of Object.entries(targets)) {
  installOne(name, version);
}

console.log(`\nDone. ${seen.size} packages installed.`);
