// Security-rules tests for /gasStock and /gasStockLedger — gas stock
// moved from an in-memory field to real Firestore this session.
// Run against the Firestore emulator (never the live project) — see
// invites_and_staff_rules.test.mjs for the emulator setup/run
// instructions, identical here.
//
// Covers: any active staff (not just owner) can read/write the current
// stock doc and append a ledger entry — selling and restocking gas are
// ordinary staff duties, not owner-only, unlike categories/products.
// Ledger update/delete stay hard-denied for everyone — it's an
// append-only audit trail.

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
const OTHER_BIZ = 'other-biz';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-leumadepos-rules-test-gas',
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

async function seedAttendant(businessId, uid) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/staff/${uid}`), {
      name: 'Attendant',
      role: 'attendant',
      active: true,
    });
  });
}

async function seedGasStock(businessId, units) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/gasStock/current`), { units });
  });
}

function asUser(uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: true }).firestore();
}

describe('gas stock (/businesses/{businessId}/gasStock/current)', () => {
  it('ALLOWS an active attendant (not just owner) to read the current stock', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedGasStock(BIZ, 840000);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(getDoc(doc(db, `businesses/${BIZ}/gasStock/current`)));
  });

  it('ALLOWS an active attendant to write the current stock — selling/restocking gas is an ordinary staff duty', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedGasStock(BIZ, 840000);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 835000 }));
  });

  it('DENIES an unauthenticated request from reading or writing the current stock', async () => {
    await seedGasStock(BIZ, 840000);
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/gasStock/current`)));
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 0 }));
  });

  it('DENIES an active staff member of a DIFFERENT business from touching this business\'s stock', async () => {
    await seedAttendant(OTHER_BIZ, 'attendant-uid');
    await seedGasStock(BIZ, 840000);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/gasStock/current`)));
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 0 }));
  });
});

describe('gas stock ledger (/businesses/{businessId}/gasStockLedger/{entryId})', () => {
  it('ALLOWS an active attendant to create a ledger entry', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/gasStockLedger/entry-1`), {
        type: 'sale',
        unitsDelta: -5000,
        staffId: 'attendant-uid',
        staffName: 'Attendant',
        saleId: 'sale-1',
        createdAt: new Date().toISOString(),
      }),
    );
  });

  it('ALLOWS an active attendant to read the ledger', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/gasStockLedger/entry-1`), {
        type: 'restock',
        unitsDelta: 14000,
        staffId: 'attendant-uid',
        staffName: 'Attendant',
        saleId: null,
        createdAt: new Date().toISOString(),
      });
    });

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(getDoc(doc(db, `businesses/${BIZ}/gasStockLedger/entry-1`)));
  });

  it('DENIES updating a ledger entry, even as the same staff member who created it', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/gasStockLedger/entry-1`), {
        type: 'sale',
        unitsDelta: -5000,
        staffId: 'attendant-uid',
        staffName: 'Attendant',
        saleId: 'sale-1',
        createdAt: new Date().toISOString(),
      });
    });

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStockLedger/entry-1`), { unitsDelta: -1 }, { merge: true }),
    );
  });

  it('DENIES deleting a ledger entry', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/gasStockLedger/entry-1`), {
        type: 'sale',
        unitsDelta: -5000,
        staffId: 'attendant-uid',
        staffName: 'Attendant',
        saleId: 'sale-1',
        createdAt: new Date().toISOString(),
      });
    });

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/gasStockLedger/entry-1`)));
  });

  it('DENIES an unauthenticated request from creating a ledger entry', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStockLedger/entry-1`), {
        type: 'sale',
        unitsDelta: -5000,
        staffId: 'nobody',
        staffName: 'Nobody',
        saleId: null,
        createdAt: new Date().toISOString(),
      }),
    );
  });
});
