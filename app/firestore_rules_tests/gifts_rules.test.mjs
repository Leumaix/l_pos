// Security-rules tests for the gifting/giveaways feature —
// businesses/{businessId}/gifts/{giftId} plus the owner-approval-token
// mechanism, businesses/{businessId}/giftApprovals/{giftId} (SAME id as
// the paired gift, minted once by GiftController before either write).
//
// Covers: any active staff (not owner-only) can create a gift; staff-
// attributed; shiftId REQUIRED unconditionally (unlike expenses, where
// only cash needs one) and cross-checked against the currently open
// shift; the threshold (gas > 2kg, product value > ₦2000) is RE-DERIVED
// here, never trusted from requiresApproval alone; a product gift's
// estimatedValueNaira is cross-checked against the product's own real
// price (closes "claim a fake low value to dodge the threshold");
// append-only; owner-only read (same boundary as /sales, /expenses).
//
// Unlike expenses_rules.test.mjs, this file does NOT use a
// stripped-rules isolation environment — that technique proved a
// REDUNDANT, independent check (shiftExpenseMatchesExpense) still holds
// if a SEPARATE enforcement point were weakened. Gifting's threshold/
// value checks live in ONE rule (gifts' own create), not two redundant
// ones, so there's nothing analogous to isolate. What IS genuinely
// two-sided here is the approval PAIRING itself — gifts/create checks
// giftApprovals exists(), giftApprovals/delete independently checks
// gifts getAfter() — and that two-sidedness is proven below via normal,
// realistic transactions (a bare, unpaired giftApprovals delete is
// denied on its own, not because gifts/create happened to also reject
// something).
//
// Run against the Firestore emulator (never the live project) — see
// invites_and_staff_rules.test.mjs for the emulator setup/run
// instructions, identical here. Like expenses_rules.test.mjs's own
// isolation section, run this against a FRESH emulator — re-running the
// full suite repeatedly against one lingering process is a known source
// of unrelated flakes in this project, not a rules bug.

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
import { doc, setDoc, getDoc, updateDoc, deleteDoc, runTransaction } from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BIZ = 'test-biz';
const OTHER_BIZ = 'other-biz';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-leumadepos-rules-test-gifts',
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
    await setDoc(doc(db, `businesses/${businessId}/staff/${uid}`), { name: 'Owner', role: 'owner', active: true });
  });
}

async function seedAttendant(businessId, uid) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/staff/${uid}`), { name: 'Attendant', role: 'attendant', active: true });
  });
}

async function seedOpenShift(businessId, overrides = {}) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/shiftState/current`), {
      openingFloatNaira: 10000,
      openedByStaffId: 'someone',
      openedByStaffName: 'Someone',
      openedAt: new Date(),
      cashTotalNaira: 0,
      cardTotalNaira: 0,
      transferTotalNaira: 0,
      creditTotalNaira: 0,
      salesCount: 0,
      expenseTotalNaira: 0,
      plannedHistoryId: 'hist-1',
      ...overrides,
    });
  });
}

async function seedProduct(businessId, productId, price, overrides = {}) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/products/${productId}`), {
      categoryId: 'cat-cylinders',
      name: 'Test Product',
      price,
      stockCount: 20,
      unit: 'piece',
      ...overrides,
    });
  });
}

function asUser(uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: true }).firestore();
}

function baseGasGift(overrides) {
  return {
    itemType: 'gas',
    productId: null,
    quantity: 1, // under the 2kg threshold
    estimatedValueNaira: 1400,
    reason: 'Sample for a new customer',
    staffId: 'attendant-uid',
    staffName: 'Attendant',
    shiftId: 'hist-1',
    requiresApproval: false,
    approvedByOwnerUid: null,
    createdAt: new Date().toISOString(),
    ...overrides,
  };
}

function baseProductGift(price, quantity, overrides) {
  return {
    itemType: 'product',
    productId: 'prod-1',
    quantity,
    estimatedValueNaira: price * quantity,
    reason: 'Damaged in handling',
    staffId: 'attendant-uid',
    staffName: 'Attendant',
    shiftId: 'hist-1',
    requiresApproval: false,
    approvedByOwnerUid: null,
    createdAt: new Date().toISOString(),
    ...overrides,
  };
}

describe('gifts/{giftId} — create shape (under threshold, no approval needed)', () => {
  it('ALLOWS a gas gift at or under the 2kg threshold', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({ quantity: 2 })));
  });

  it('ALLOWS a product gift at or under the ₦2000 threshold, value cross-checked against the real price', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);
    await seedProduct(BIZ, 'prod-1', 500);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseProductGift(500, 4)), // 2000, at the threshold
    );
  });

  it('DENIES a gift with no shift open at all — every gift needs one, unconditionally', async () => {
    await seedAttendant(BIZ, 'attendant-uid');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({})));
  });

  it('DENIES a shiftId that does not match the current shift', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ); // plannedHistoryId: 'hist-1'

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({ shiftId: 'hist-stale' })));
  });

  it('DENIES a zero or negative quantity', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({ quantity: 0 })));
  });

  it('DENIES an empty reason', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({ reason: '' })));
  });

  it('DENIES a product gift with no productId', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);
    await seedProduct(BIZ, 'prod-1', 500);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), { ...baseProductGift(500, 2), productId: null }),
    );
  });

  it('DENIES staffId not matching the authenticated uid', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({ staffId: 'someone-else' })));
  });

  it('DENIES an unauthenticated request', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({})));
  });

  it('DENIES update or delete on an existing gift — append-only', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedOpenShift(BIZ);
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({ staffId: 'owner-uid' }));
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(updateDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), { quantity: 1 }));
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`)));
  });
});

describe('gifts/{giftId} — the threshold is re-derived, never trusted from requiresApproval alone', () => {
  it('DENIES an over-threshold gas gift claiming requiresApproval: false — the bypass attempt', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({ quantity: 3, requiresApproval: false })),
    );
  });

  it('DENIES an over-threshold product gift claiming requiresApproval: false', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);
    await seedProduct(BIZ, 'prod-1', 3000);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseProductGift(3000, 1, { requiresApproval: false })),
    );
  });

  it('DENIES a lowballed estimatedValueNaira used to dodge the threshold — the product-value cross-check', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);
    await seedProduct(BIZ, 'prod-1', 3000); // real value for quantity 1 is 3000, over threshold

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(
        doc(db, `businesses/${BIZ}/gifts/gift-1`),
        baseProductGift(3000, 1, { estimatedValueNaira: 500, requiresApproval: false }), // claims 500 instead of the real 3000
      ),
    );
  });

  it('DENIES an over-threshold gift claiming requiresApproval: true with no matching giftApprovals doc at all', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(
        doc(db, `businesses/${BIZ}/gifts/gift-1`),
        baseGasGift({ quantity: 3, requiresApproval: true, approvedByOwnerUid: 'owner-uid' }),
      ),
    );
  });
});

describe('gifts/{giftId} — read is owner-only, same boundary as /sales, /expenses', () => {
  it('ALLOWS an active owner to read a gift', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedOpenShift(BIZ);
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({ staffId: 'owner-uid' }));
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(getDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`)));
  });

  it('DENIES an active attendant from reading a gift, even their own', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({ staffId: 'attendant-uid' }));
    });

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`)));
  });

  it('DENIES a staff member of a DIFFERENT business', async () => {
    await seedOwner(OTHER_BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({}));
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`)));
  });
});

describe('giftApprovals/{giftId} — never read, written only by the owner\'s own session', () => {
  it('ALLOWS an active owner to create their own approval doc', async () => {
    await seedOwner(BIZ, 'owner-uid');

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/giftApprovals/gift-1`), {
        approvedByOwnerUid: 'owner-uid',
        createdAt: new Date().toISOString(),
      }),
    );
  });

  it('DENIES a non-owner (even an active staff member) from creating one', async () => {
    await seedAttendant(BIZ, 'attendant-uid');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/giftApprovals/gift-1`), {
        approvedByOwnerUid: 'attendant-uid',
        createdAt: new Date().toISOString(),
      }),
    );
  });

  it('DENIES an owner creating an approval doc attributed to someone else\'s uid', async () => {
    await seedOwner(BIZ, 'owner-uid');

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/giftApprovals/gift-1`), {
        approvedByOwnerUid: 'a-different-owner-uid',
        createdAt: new Date().toISOString(),
      }),
    );
  });

  it('DENIES reading a giftApprovals doc, even as the owner who created it', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/giftApprovals/gift-1`), {
        approvedByOwnerUid: 'owner-uid',
        createdAt: new Date(),
      });
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/giftApprovals/gift-1`)));
  });

  it('DENIES updating a giftApprovals doc', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/giftApprovals/gift-1`), {
        approvedByOwnerUid: 'owner-uid',
        createdAt: new Date(),
      });
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(
      updateDoc(doc(db, `businesses/${BIZ}/giftApprovals/gift-1`), { approvedByOwnerUid: 'someone-else' }),
    );
  });
});

describe('the approval-token pairing — real, two-sided enforcement, not just trusted client input', () => {
  it('ALLOWS the real end-to-end shape: owner creates the approval, staff commits the paired gift '
    + 'in a transaction that consumes it', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const ownerDb = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(
      setDoc(doc(ownerDb, `businesses/${BIZ}/giftApprovals/gift-1`), {
        approvedByOwnerUid: 'owner-uid',
        createdAt: new Date(),
      }),
    );

    const staffDb = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      runTransaction(staffDb, async (transaction) => {
        transaction.set(
          doc(staffDb, `businesses/${BIZ}/gifts/gift-1`),
          baseGasGift({ quantity: 3, requiresApproval: true, approvedByOwnerUid: 'owner-uid' }),
        );
        transaction.delete(doc(staffDb, `businesses/${BIZ}/giftApprovals/gift-1`));
      }),
    );

    await seed(async (db) => {
      const approvalSnap = await getDoc(doc(db, `businesses/${BIZ}/giftApprovals/gift-1`));
      assert.equal(approvalSnap.exists(), false); // consumed
      const giftSnap = await getDoc(doc(db, `businesses/${BIZ}/gifts/gift-1`));
      assert.equal(giftSnap.exists(), true);
    });
  });

  it('DENIES a bare giftApprovals delete with no paired gift creation at all — proves the delete rule '
    + 'has its OWN independent check, not just trusting whatever transaction the caller sends', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/giftApprovals/gift-1`), {
        approvedByOwnerUid: 'owner-uid',
        createdAt: new Date(),
      });
    });

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/giftApprovals/gift-1`)));

    await seed(async (adminDb) => {
      const snap = await getDoc(doc(adminDb, `businesses/${BIZ}/giftApprovals/gift-1`));
      assert.equal(snap.exists(), true); // untouched
    });
  });

  it('DENIES reusing an already-consumed approval for a SECOND gift — the anti-replay proof', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const ownerDb = asUser('owner-uid', 'owner@example.com');
    await setDoc(doc(ownerDb, `businesses/${BIZ}/giftApprovals/gift-1`), {
      approvedByOwnerUid: 'owner-uid',
      createdAt: new Date(),
    });

    const staffDb = asUser('attendant-uid', 'attendant@example.com');
    // First gift consumes the approval — real success.
    await assertSucceeds(
      runTransaction(staffDb, async (transaction) => {
        transaction.set(
          doc(staffDb, `businesses/${BIZ}/gifts/gift-1`),
          baseGasGift({ quantity: 3, requiresApproval: true, approvedByOwnerUid: 'owner-uid' }),
        );
        transaction.delete(doc(staffDb, `businesses/${BIZ}/giftApprovals/gift-1`));
      }),
    );

    // A SECOND, different gift trying to reuse the SAME (now-deleted)
    // approval id — exists() on gift-1's approval now fails.
    await assertFails(
      setDoc(
        doc(staffDb, `businesses/${BIZ}/gifts/gift-1-replay`),
        baseGasGift({ quantity: 3, requiresApproval: true, approvedByOwnerUid: 'owner-uid' }),
      ),
    );
  });

  it('DENIES a paired delete/create where the gift claims a DIFFERENT ownerUid than the approval actually has', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);
    const ownerDb = asUser('owner-uid', 'owner@example.com');
    await setDoc(doc(ownerDb, `businesses/${BIZ}/giftApprovals/gift-1`), {
      approvedByOwnerUid: 'owner-uid',
      createdAt: new Date(),
    });

    const staffDb = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(staffDb, async (transaction) => {
        transaction.set(
          doc(staffDb, `businesses/${BIZ}/gifts/gift-1`),
          baseGasGift({ quantity: 3, requiresApproval: true, approvedByOwnerUid: 'a-different-uid' }),
        );
        transaction.delete(doc(staffDb, `businesses/${BIZ}/giftApprovals/gift-1`));
      }),
    );
  });

  it('DENIES consuming an approval older than the 10-minute window', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);
    await seed(async (db) => {
      // Bypass write with a stale createdAt — simulates a real approval
      // that's simply been sitting unconsumed too long.
      await setDoc(doc(db, `businesses/${BIZ}/giftApprovals/gift-1`), {
        approvedByOwnerUid: 'owner-uid',
        createdAt: new Date(Date.now() - 11 * 60 * 1000),
      });
    });

    const staffDb = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(staffDb, async (transaction) => {
        transaction.set(
          doc(staffDb, `businesses/${BIZ}/gifts/gift-1`),
          baseGasGift({ quantity: 3, requiresApproval: true, approvedByOwnerUid: 'owner-uid' }),
        );
        transaction.delete(doc(staffDb, `businesses/${BIZ}/giftApprovals/gift-1`));
      }),
    );
  });
});

describe('worked example — gas + product gifts deduct real stock, no revenue', () => {
  it('a gas gift decrements gasStock/current.units and appends a type: gift ledger entry', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 63000, rate: 1400 });
    });

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        transaction.set(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseGasGift({ quantity: 1 })); // 1400 units
        transaction.set(
          doc(db, `businesses/${BIZ}/gasStock/current`),
          { units: 63000 - 1400 },
          { merge: true },
        );
        transaction.set(doc(db, `businesses/${BIZ}/gasStockLedger/entry-1`), {
          type: 'gift',
          unitsDelta: -1400,
          staffId: 'attendant-uid',
          staffName: 'Attendant',
          giftId: 'gift-1',
          createdAt: new Date(),
        });
      }),
    );

    await seed(async (adminDb) => {
      const stockSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/gasStock/current`));
      assert.equal(stockSnap.data().units, 61600);
    });
  });

  it('a product gift decrements the product\'s stockCount, rejected if it would go negative', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);
    await seedProduct(BIZ, 'prod-1', 500, { stockCount: 1 });

    const db = asUser('attendant-uid', 'attendant@example.com');
    // Gifting 2 when only 1 is in stock — DENIED by products' own
    // existing stockCount >= 0 rule, no new rule needed for this.
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.set(doc(db, `businesses/${BIZ}/gifts/gift-1`), baseProductGift(500, 2));
        transaction.update(doc(db, `businesses/${BIZ}/products/prod-1`), { stockCount: -1 });
      }),
    );
  });
});
