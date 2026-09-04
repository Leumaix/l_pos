// Security-rules tests for the owner-editable gas tank capacity setting.
// Run against the Firestore emulator (never the live project) — see
// invites_and_staff_rules.test.mjs for the emulator setup/run
// instructions, identical here.
//
// Covers: only an active owner can update the business doc at all; the
// update is scoped to settings.gasTankCapacityKg specifically — not the
// whole document, not other settings fields, not business creation or
// deletion.

import { before, after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc } from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BIZ = 'test-biz';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    // Distinct project ID from invites_and_staff_rules.test.mjs — Node's
    // test runner may run files concurrently, and both files share one
    // running emulator; separate projects keep their clearFirestore()
    // calls from racing each other.
    projectId: 'demo-leumadepos-rules-test-business',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: 'localhost',
      port: 8090,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

async function seed(setupFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setupFn(context.firestore());
  });
}

async function seedOwner(businessId, uid) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/staff/${uid}`), {
      name: 'Owner',
      role: 'owner',
      active: true,
    });
  });
}

async function seedAttendant(businessId, uid) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/staff/${uid}`), {
      name: 'Attendant',
      role: 'attendant',
      active: true,
    });
  });
}

function asUser(uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: true }).firestore();
}

describe('business settings (allow update on /businesses/{businessId})', () => {
  it('ALLOWS an active owner to set gasTankCapacityKg when settings does not exist yet', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}`), { name: 'Test Biz' }); // no settings map at all
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}`), { settings: { gasTankCapacityKg: 500 } }, { merge: true }),
    );
  });

  it('ALLOWS an active owner to update gasTankCapacityKg when settings already exists (positive control)', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}`), { name: 'Test Biz', settings: { gasTankCapacityKg: 100 } });
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}`), { settings: { gasTankCapacityKg: 750 } }, { merge: true }),
    );

    await seed(async (adminDb) => {
      const snap = await getDoc(doc(adminDb, `businesses/${BIZ}`));
      assert.equal(snap.data().settings.gasTankCapacityKg, 750);
    });
  });

  it('DENIES a non-owner (active attendant) from updating the business doc at all', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}`), { name: 'Test Biz', settings: { gasTankCapacityKg: 100 } });
    });

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}`), { settings: { gasTankCapacityKg: 750 } }, { merge: true }),
    );
  });

  it('DENIES an unauthenticated request from updating the business doc', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}`), { name: 'Test Biz', settings: { gasTankCapacityKg: 100 } });
    });

    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}`), { settings: { gasTankCapacityKg: 750 } }, { merge: true }),
    );
  });

  it('DENIES an owner from changing a top-level field OTHER than settings in the same write', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}`), { name: 'Test Biz', settings: { gasTankCapacityKg: 100 } });
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(
      setDoc(
        doc(db, `businesses/${BIZ}`),
        { name: 'Renamed Biz', settings: { gasTankCapacityKg: 750 } },
        { merge: true },
      ),
    );
  });

  it('DENIES an owner from changing a settings field OTHER than gasTankCapacityKg', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}`), {
        name: 'Test Biz',
        settings: { gasTankCapacityKg: 100, gasRateNairaPerKg: 1400 },
      });
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(
      setDoc(
        doc(db, `businesses/${BIZ}`),
        { settings: { gasTankCapacityKg: 100, gasRateNairaPerKg: 1500 } },
        { merge: true },
      ),
    );
  });

  it('still ALLOWS gasTankCapacityKg alone when other settings fields already exist, and leaves them untouched', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}`), {
        name: 'Test Biz',
        settings: { gasTankCapacityKg: 100, gasRateNairaPerKg: 1400 },
      });
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}`), { settings: { gasTankCapacityKg: 320 } }, { merge: true }),
    );

    await seed(async (adminDb) => {
      const snap = await getDoc(doc(adminDb, `businesses/${BIZ}`));
      assert.equal(snap.data().settings.gasTankCapacityKg, 320);
      assert.equal(snap.data().settings.gasRateNairaPerKg, 1400); // untouched
    });
  });

  it('DENIES creating a new business document, even as an owner of a DIFFERENT business', async () => {
    await seedOwner(BIZ, 'owner-uid');
    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(setDoc(doc(db, 'businesses/brand-new-biz'), { name: 'New Biz' }));
  });

  it('DENIES deleting the business document, even as its own active owner', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}`), { name: 'Test Biz', settings: { gasTankCapacityKg: 100 } });
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}`)));
  });
});
