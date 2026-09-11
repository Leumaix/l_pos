// Security-rules tests for /shiftState/current and /shiftHistory — the
// Open Day / End Day feature. Run against the Firestore emulator (never
// the live project) — see invites_and_staff_rules.test.mjs for the
// emulator setup/run instructions, identical here.
//
// Covers: existence of shiftState/current IS "a shift is open" (no
// status field) — open only succeeds when none exists (Firestore's own
// create-vs-update classification structurally blocks opening a second
// one while one is live); any active staff member (not just owner) can
// open, apply sale-time totals increments, and close; closing a shift
// (deleting shiftState/current) is only allowed when paired, in the SAME
// transaction, with a real shiftHistory record at the exact
// plannedHistoryId minted at open time, whose expectedCashNaira is
// arithmetically honest against the totals being deleted — a bare
// delete, or one paired with a wrong id or fabricated expectedCashNaira,
// is rejected. shiftHistory read is owner-only, matching /sales; create
// is open to any active staff (closing is not owner-only); update/delete
// are hard-denied — append-only, same as every other ledger in this app.

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
import { doc, setDoc, getDoc, deleteDoc, runTransaction } from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BIZ = 'test-biz';
const OTHER_BIZ = 'other-biz';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-leumadepos-rules-test-shift',
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

const OPEN_SHIFT_BASE = {
  openingFloatNaira: 10000,
  openedByStaffId: 'someone-uid',
  openedByStaffName: 'Someone',
  openedAt: new Date(),
  cashTotalNaira: 25000,
  cardTotalNaira: 8000,
  transferTotalNaira: 0,
  creditTotalNaira: 0,
  salesCount: 4,
  expenseTotalNaira: 0,
  plannedHistoryId: 'hist-1',
};

async function seedOpenShift(businessId, overrides = {}) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/shiftState/current`), { ...OPEN_SHIFT_BASE, ...overrides });
  });
}

function asUser(uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: true }).firestore();
}

describe('shiftState/current — open', () => {
  it('ALLOWS an active attendant to open a shift when none exists', async () => {
    await seedAttendant(BIZ, 'attendant-uid');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/shiftState/current`), {
        openingFloatNaira: 15000,
        openedByStaffId: 'attendant-uid',
        openedByStaffName: 'Attendant',
        openedAt: new Date(),
        cashTotalNaira: 0,
        cardTotalNaira: 0,
        transferTotalNaira: 0,
        creditTotalNaira: 0,
        salesCount: 0,
        plannedHistoryId: 'hist-new',
      }),
    );
  });

  it('ALLOWS opening with a zero float — a legitimate starting point, unlike gas rate/tank capacity', async () => {
    await seedOwner(BIZ, 'owner-uid');

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/shiftState/current`), {
        openingFloatNaira: 0,
        openedByStaffId: 'owner-uid',
        openedByStaffName: 'Owner',
        openedAt: new Date(),
        cashTotalNaira: 0,
        cardTotalNaira: 0,
        transferTotalNaira: 0,
        creditTotalNaira: 0,
        salesCount: 0,
        plannedHistoryId: 'hist-new',
      }),
    );
  });

  it('DENIES opening with a negative float', async () => {
    await seedAttendant(BIZ, 'attendant-uid');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/shiftState/current`), {
        openingFloatNaira: -100,
        openedByStaffId: 'attendant-uid',
        openedByStaffName: 'Attendant',
        openedAt: new Date(),
        cashTotalNaira: 0,
        cardTotalNaira: 0,
        transferTotalNaira: 0,
        creditTotalNaira: 0,
        salesCount: 0,
        plannedHistoryId: 'hist-new',
      }),
    );
  });

  it('DENIES opening a second shift while one is already open — the safe default for a forgotten close, '
    + 'falling straight out of create-vs-update classification', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/shiftState/current`), {
        openingFloatNaira: 20000,
        openedByStaffId: 'attendant-uid',
        openedByStaffName: 'Attendant',
        openedAt: new Date(),
        cashTotalNaira: 0,
        cardTotalNaira: 0,
        transferTotalNaira: 0,
        creditTotalNaira: 0,
        salesCount: 0,
        plannedHistoryId: 'hist-2',
      }),
    );
  });

  it('DENIES an unauthenticated request from opening a shift', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/shiftState/current`), {
        openingFloatNaira: 10000,
        openedByStaffId: 'nobody',
        openedByStaffName: 'Nobody',
        openedAt: new Date(),
        cashTotalNaira: 0,
        cardTotalNaira: 0,
        transferTotalNaira: 0,
        creditTotalNaira: 0,
        salesCount: 0,
        plannedHistoryId: 'hist-x',
      }),
    );
  });
});

describe('shiftState/current — read and sale-time totals update', () => {
  it('ALLOWS an active attendant to read the current shift', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(getDoc(doc(db, `businesses/${BIZ}/shiftState/current`)));
  });

  it(
    'ALLOWS an active staff member to increment the totals fields when paired, in the same transaction, '
    + 'with the exact new sale those totals actually came from — the real checkout-time write. See '
    + 'checkout_commit_rules.test.mjs for the full split-tender/lastSaleId-pairing coverage; this is the '
    + 'minimal version scoped to shiftState/current\'s own rule.',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedOpenShift(BIZ);

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertSucceeds(
        runTransaction(db, async (transaction) => {
          transaction.set(doc(db, `businesses/${BIZ}/sales/sale-1`), {
            receiptNumber: 'sale-1',
            items: [],
            subtotal: 1000,
            total: 1000,
            payments: [{ method: 'cash', amountNaira: 1000 }],
            staffId: 'attendant-uid',
            staffName: 'Attendant',
            createdAt: new Date().toISOString(),
          });
          transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
            cashTotalNaira: 26000, // 25000 (seeded) + 1000
            salesCount: 5,
            lastSaleId: 'sale-1',
          });
        }),
      );
    },
  );

  it(
    'DENIES a bare totals update with no lastSaleId at all — the old, unpaired shape this phase '
    + 'closes off entirely, not just narrows',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedOpenShift(BIZ);

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertFails(
        setDoc(
          doc(db, `businesses/${BIZ}/shiftState/current`),
          { cashTotalNaira: 26000, salesCount: 5 },
          { merge: true },
        ),
      );
    },
  );

  it('DENIES touching openingFloatNaira in a sale-time-shaped update', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(
        doc(db, `businesses/${BIZ}/shiftState/current`),
        { cashTotalNaira: 26000, openingFloatNaira: 999999 },
        { merge: true },
      ),
    );
  });

  it('DENIES touching openedByStaffId/openedByStaffName/plannedHistoryId', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(
        doc(db, `businesses/${BIZ}/shiftState/current`),
        { plannedHistoryId: 'hijacked' },
        { merge: true },
      ),
    );
  });

  it('DENIES a staff member of a DIFFERENT business from reading or updating this business\'s shift', async () => {
    await seedAttendant(OTHER_BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/shiftState/current`)));
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/shiftState/current`), { salesCount: 99 }, { merge: true }),
    );
  });
});

describe('shiftState/current — close (delete), paired with an honest shiftHistory record', () => {
  it('ALLOWS closing when the delete is paired, in the same transaction, with a correctly-id\'d, '
    + 'arithmetically consistent shiftHistory record', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ); // openingFloatNaira: 10000, cashTotalNaira: 25000 -> expected 35000

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        transaction.delete(doc(db, `businesses/${BIZ}/shiftState/current`));
        transaction.set(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`), {
          ...OPEN_SHIFT_BASE,
          countedCashNaira: 35000,
          expectedCashNaira: 35000,
          varianceNaira: 0,
          closedByStaffId: 'attendant-uid',
          closedByStaffName: 'Attendant',
          closedAt: new Date(),
        });
      }),
    );

    await seed(async (adminDb) => {
      const stateSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/shiftState/current`));
      assert.equal(stateSnap.exists(), false);
      const histSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/shiftHistory/hist-1`));
      assert.equal(histSnap.exists(), true);
      assert.equal(histSnap.data().expectedCashNaira, 35000);
    });
  });

  it('ALLOWS closing with a nonzero variance too — the check is about arithmetic honesty, not a zero result', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedOpenShift(BIZ); // expected 35000

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        transaction.delete(doc(db, `businesses/${BIZ}/shiftState/current`));
        transaction.set(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`), {
          ...OPEN_SHIFT_BASE,
          countedCashNaira: 34500, // ₦500 short
          expectedCashNaira: 35000,
          varianceNaira: -500,
          closedByStaffId: 'owner-uid',
          closedByStaffName: 'Owner',
          closedAt: new Date(),
        });
      }),
    );
  });

  it('DENIES a bare delete with no paired shiftHistory write at all — the actual data-loss risk this exists to close', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/shiftState/current`)));

    await seed(async (adminDb) => {
      const stateSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/shiftState/current`));
      assert.equal(stateSnap.exists(), true); // untouched
    });
  });

  it('DENIES a delete paired with a shiftHistory write at the WRONG id (not plannedHistoryId)', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ); // plannedHistoryId: 'hist-1'

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.delete(doc(db, `businesses/${BIZ}/shiftState/current`));
        transaction.set(doc(db, `businesses/${BIZ}/shiftHistory/some-other-id`), {
          ...OPEN_SHIFT_BASE,
          countedCashNaira: 35000,
          expectedCashNaira: 35000,
          varianceNaira: 0,
          closedByStaffId: 'attendant-uid',
          closedByStaffName: 'Attendant',
          closedAt: new Date(),
        });
      }),
    );
  });

  it('DENIES a delete paired with the correct id but a fabricated expectedCashNaira — the honesty check, '
    + 'not just existence-pairing', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ); // openingFloatNaira: 10000, cashTotalNaira: 25000 -> true expected is 35000

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.delete(doc(db, `businesses/${BIZ}/shiftState/current`));
        transaction.set(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`), {
          ...OPEN_SHIFT_BASE,
          countedCashNaira: 999999,
          expectedCashNaira: 999999, // fabricated — doesn't match openingFloat + cashTotal
          varianceNaira: 0,
          closedByStaffId: 'attendant-uid',
          closedByStaffName: 'Attendant',
          closedAt: new Date(),
        });
      }),
    );
  });

  it('DENIES a delete paired with a shiftHistory write missing closedAt entirely', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.delete(doc(db, `businesses/${BIZ}/shiftState/current`));
        transaction.set(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`), {
          ...OPEN_SHIFT_BASE,
          countedCashNaira: 35000,
          expectedCashNaira: 35000,
          varianceNaira: 0,
          closedByStaffId: 'attendant-uid',
          closedByStaffName: 'Attendant',
          // closedAt omitted
        });
      }),
    );
  });
});

describe('shiftHistory/{shiftId}', () => {
  it('ALLOWS an active owner to read shift history', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`), {
        ...OPEN_SHIFT_BASE,
        countedCashNaira: 35000,
        expectedCashNaira: 35000,
        varianceNaira: 0,
        closedByStaffId: 'owner-uid',
        closedByStaffName: 'Owner',
        closedAt: new Date(),
      });
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(getDoc(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`)));
  });

  it('DENIES an active attendant from reading shift history — same revenue boundary as /sales', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`), {
        ...OPEN_SHIFT_BASE,
        countedCashNaira: 35000,
        expectedCashNaira: 35000,
        varianceNaira: 0,
        closedByStaffId: 'attendant-uid',
        closedByStaffName: 'Attendant',
        closedAt: new Date(),
      });
    });

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`)));
  });

  it('DENIES updating or deleting a shiftHistory record, even as the owner — append-only', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`), {
        ...OPEN_SHIFT_BASE,
        countedCashNaira: 35000,
        expectedCashNaira: 35000,
        varianceNaira: 0,
        closedByStaffId: 'owner-uid',
        closedByStaffName: 'Owner',
        closedAt: new Date(),
      });
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`), { varianceNaira: 0 }, { merge: true }),
    );
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`)));
  });
});
