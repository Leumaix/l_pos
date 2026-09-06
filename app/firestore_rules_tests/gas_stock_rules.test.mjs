// Security-rules tests for /gasStock and /gasStockLedger — gas stock
// moved from an in-memory field to real Firestore this session.
// Run against the Firestore emulator (never the live project) — see
// invites_and_staff_rules.test.mjs for the emulator setup/run
// instructions, identical here.
//
// Covers: any active staff (not just owner) can read the current stock
// doc, and can move ONLY `units` (a sale or restock delta) — selling and
// restocking gas are ordinary staff duties, not owner-only, unlike
// categories/products. Changing `rate` is owner-only, and only when the
// `units` written in the same update is mathematically consistent with
// the rate change (same physical kg, re-expressed at the new rate) —
// see the "gas stock rate change" describe block below. Ledger
// update/delete stay hard-denied for everyone — it's an append-only
// audit trail.

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

async function seedOwner(businessId, uid) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/staff/${uid}`), {
      name: 'Owner',
      role: 'owner',
      active: true,
    });
  });
}

async function seedGasStock(businessId, units, rate) {
  await seed(async (db) => {
    await setDoc(
      doc(db, `businesses/${businessId}/gasStock/current`),
      rate === undefined ? { units } : { units, rate },
    );
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

  it('DENIES an active attendant from touching `rate` at all, even alongside a units change', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedGasStock(BIZ, 28000, 1400);

    const db = asUser('attendant-uid', 'attendant@example.com');
    // rate must actually differ from what's stored — writing back an
    // identical value is a no-op diff (affectedKeys() would be empty),
    // which wouldn't exercise this denial at all.
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 30000, rate: 1500 }, { merge: true }),
    );
  });

  it('DENIES an active attendant from dropping the `rate` field via a non-merge overwrite', async () => {
    // The real client always uses a merge-set for sale/restock deltas, but
    // rules can't trust client intent — a bare (non-merge) setDoc that
    // omits `rate` entirely still counts as touching it (the field is
    // removed), so this must be denied by the same units-only rule, not
    // silently allowed to wipe the rate.
    await seedAttendant(BIZ, 'attendant-uid');
    await seedGasStock(BIZ, 28000, 1400);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 27000 }));
  });

  it('DENIES deleting the current stock doc, even as an owner', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedGasStock(BIZ, 28000, 1400);

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/gasStock/current`)));
  });

  it('ALLOWS an active attendant to create the current stock doc for the first time via a units-only restock/sale', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    // No seedGasStock call — the doc genuinely doesn't exist yet.
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 14000 }, { merge: true }));
  });

  it('DENIES an active attendant from creating the current stock doc with anything other than `units`', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 0, rate: 1400 }, { merge: true }),
    );
  });
});

describe('gas stock rate initialization (/businesses/{businessId}/gasStock/current, first-ever create, owner-only)', () => {
  it('ALLOWS an active owner to set the very first rate on a business with no gasStock doc yet', async () => {
    await seedOwner(BIZ, 'owner-uid');
    // No seedGasStock call — this business has never had a rate or any
    // stock at all, matching a freshly onboarded business.
    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { rate: 1400, units: 0 }, { merge: true }),
    );

    await seed(async (adminDb) => {
      const snap = await getDoc(doc(adminDb, `businesses/${BIZ}/gasStock/current`));
      assert.equal(snap.data().rate, 1400);
      assert.equal(snap.data().units, 0);
    });
  });

  it('DENIES a non-owner (active attendant) from setting the very first rate', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { rate: 1400, units: 0 }, { merge: true }),
    );
  });

  it('DENIES an owner from initializing with a non-zero units value', async () => {
    await seedOwner(BIZ, 'owner-uid');
    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { rate: 1400, units: 5000 }, { merge: true }),
    );
  });

  it('DENIES an owner from initializing with a non-positive rate', async () => {
    await seedOwner(BIZ, 'owner-uid');
    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { rate: 0, units: 0 }, { merge: true }));
  });

  it('DENIES an unauthenticated request from initializing the rate', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { rate: 1400, units: 0 }, { merge: true }),
    );
  });
});

describe('gas stock rate change (/businesses/{businessId}/gasStock/current, owner-only)', () => {
  it('ALLOWS an active owner to change the rate when units is recomputed consistently (positive control)', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedGasStock(BIZ, 28000, 1400); // 20kg at 1400/kg

    const db = asUser('owner-uid', 'owner@example.com');
    // Same 20kg, re-expressed at 1500/kg = 30000 units.
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 30000, rate: 1500 }, { merge: true }),
    );

    await seed(async (adminDb) => {
      const snap = await getDoc(doc(adminDb, `businesses/${BIZ}/gasStock/current`));
      assert.equal(snap.data().rate, 1500);
      assert.equal(snap.data().units, 30000);
    });
  });

  it('ALLOWS a units value within the small rounding tolerance of the exact conversion', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedGasStock(BIZ, 28000, 1400); // 20kg

    const db = asUser('owner-uid', 'owner@example.com');
    // Exact conversion at 1500/kg is 30000 — 30001 is a rounding-sized nudge.
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 30001, rate: 1500 }, { merge: true }),
    );
  });

  it('DENIES an owner from inflating units under cover of a rate change', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedGasStock(BIZ, 28000, 1400); // 20kg

    const db = asUser('owner-uid', 'owner@example.com');
    // Exact conversion at 1500/kg is 30000 — 40000 would silently add ~6.7kg
    // of stock that never actually arrived.
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 40000, rate: 1500 }, { merge: true }),
    );
  });

  it('DENIES an owner from deflating units under cover of a rate change', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedGasStock(BIZ, 28000, 1400); // 20kg

    const db = asUser('owner-uid', 'owner@example.com');
    // Exact conversion at 1500/kg is 30000 — 10000 would silently erase
    // most of the recorded stock.
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 10000, rate: 1500 }, { merge: true }),
    );
  });

  it('DENIES a non-owner (active attendant) from changing the rate even with mathematically consistent units', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedGasStock(BIZ, 28000, 1400); // 20kg

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 30000, rate: 1500 }, { merge: true }),
    );
  });

  it('DENIES an unauthenticated request from changing the rate', async () => {
    await seedGasStock(BIZ, 28000, 1400);
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 30000, rate: 1500 }, { merge: true }),
    );
  });

  it('DENIES an owner from setting a non-positive rate, even with the "consistent" units for it', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedGasStock(BIZ, 28000, 1400); // 20kg

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 0, rate: 0 }, { merge: true }),
    );
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: -20000, rate: -1400 }, { merge: true }),
    );
  });

  it('DENIES an owner from changing the rate without recomputing units at all (units left stale)', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedGasStock(BIZ, 28000, 1400); // 20kg

    const db = asUser('owner-uid', 'owner@example.com');
    // rate changes but units is untouched — no longer represents 20kg at
    // the new rate, and this isn't a pure units-only write either (rate
    // changed), so neither update rule should match.
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { rate: 1500 }, { merge: true }));
  });

  it('DENIES an owner from changing a field other than rate/units in the same write', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedGasStock(BIZ, 28000, 1400); // 20kg

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(
      setDoc(
        doc(db, `businesses/${BIZ}/gasStock/current`),
        { units: 30000, rate: 1500, note: 'sneaked in' },
        { merge: true },
      ),
    );
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
