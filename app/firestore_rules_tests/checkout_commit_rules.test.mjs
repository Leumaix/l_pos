// Security-rules tests for the atomic checkout commit — the real
// Firestore transaction FirebaseCheckoutRepository.commitSale performs
// (sale record + gas stock/ledger + product stockCount decrements +
// customer balance/transaction), exercised as ONE real transaction, not
// isolated single-document writes. This is the same lesson this
// session's invite-delete bug taught: a rule can allow every operation
// individually and still deny (or wrongly allow) the combined write —
// only testing the real shape catches that.
//
// Run against the Firestore emulator (never the live project) — see
// invites_and_staff_rules.test.mjs for the emulator setup/run
// instructions, identical here.

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
import { doc, setDoc, getDoc, updateDoc, runTransaction } from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BIZ = 'test-biz';
const OTHER_BIZ = 'other-biz';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-leumadepos-rules-test-checkout',
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

async function seedProduct(businessId, productId, stockCount) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/products/${productId}`), {
      categoryId: 'cat-cylinders',
      name: '6kg Cylinder',
      price: 15000,
      stockCount,
      unit: 'piece',
    });
  });
}

async function seedGasStock(businessId, units) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/gasStock/current`), { units });
  });
}

async function seedCustomer(businessId, customerId, balance) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/customers/${customerId}`), {
      name: 'Ngozi Eze',
      phone: '08051112222',
      balance,
    });
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
      plannedHistoryId: 'hist-1',
      ...overrides,
    });
  });
}

function asUser(uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: true }).firestore();
}

describe('checkout commit — the real transaction FirebaseCheckoutRepository.commitSale performs', () => {
  it('ALLOWS a cash sale (sale record + product stockCount decrement + shift totals increment) as one transaction', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedProduct(BIZ, 'prod-1', 9);
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        transaction.set(doc(db, `businesses/${BIZ}/sales/sale-1`), {
          receiptNumber: 'sale-1',
          items: [],
          subtotal: 15000,
          total: 15000,
          method: 'cash',
          cashGiven: 15000,
          changeGiven: 0,
          customerId: null,
          customerName: null,
          staffId: 'attendant-uid',
          staffName: 'Attendant',
          createdAt: new Date().toISOString(),
        });
        transaction.update(doc(db, `businesses/${BIZ}/products/prod-1`), { stockCount: 8 });
        // The shift-time totals write FirebaseCheckoutRepository.commitSale
        // now performs alongside every other mutation in this one
        // transaction — see FirebaseInventoryRepository/checkout's doc
        // comments and shift_rules.test.mjs for shiftState/current's own
        // rules coverage.
        transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
          cashTotalNaira: 15000,
          salesCount: 1,
        });
      }),
    );

    await seed(async (adminDb) => {
      const snap = await getDoc(doc(adminDb, `businesses/${BIZ}/products/prod-1`));
      assert.equal(snap.data().stockCount, 8);
      const shiftSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/shiftState/current`));
      assert.equal(shiftSnap.data().cashTotalNaira, 15000);
      assert.equal(shiftSnap.data().salesCount, 1);
    });
  });

  it('ALLOWS a full mixed sale — sale + gas stock/ledger + product decrement + customer balance/transaction + shift totals — as one transaction', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedProduct(BIZ, 'prod-1', 9);
    await seedGasStock(BIZ, 840000);
    await seedCustomer(BIZ, 'cust-1', 2000);
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        transaction.set(doc(db, `businesses/${BIZ}/sales/sale-2`), {
          receiptNumber: 'sale-2',
          items: [],
          subtotal: 22000,
          total: 22000,
          method: 'customerAccount',
          cashGiven: null,
          changeGiven: null,
          customerId: 'cust-1',
          customerName: 'Ngozi Eze',
          staffId: 'attendant-uid',
          staffName: 'Attendant',
          createdAt: new Date().toISOString(),
        });
        transaction.set(
          doc(db, `businesses/${BIZ}/gasStock/current`),
          { units: 833000 },
          { merge: true },
        );
        transaction.set(doc(db, `businesses/${BIZ}/gasStockLedger/sale-2-gas`), {
          type: 'sale',
          unitsDelta: -7000,
          staffId: 'attendant-uid',
          staffName: 'Attendant',
          saleId: 'sale-2',
          createdAt: new Date().toISOString(),
        });
        transaction.update(doc(db, `businesses/${BIZ}/products/prod-1`), { stockCount: 8 });
        // lastTransactionId pairs this balance change with the ledger
        // entry below, in the SAME transaction — required by the
        // /customers update rule's getAfter() check (see firestore.rules).
        transaction.update(doc(db, `businesses/${BIZ}/customers/cust-1`), {
          balance: 24000,
          lastTransactionId: 'sale-2',
        });
        transaction.set(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/sale-2`), {
          type: 'creditSale',
          amountNaira: 22000,
          balanceAfter: 24000,
          createdAt: new Date().toISOString(),
          saleId: 'sale-2',
        });
        // A customerAccount sale increments creditTotalNaira, not
        // cashTotalNaira — no physical cash entered the drawer.
        transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
          creditTotalNaira: 22000,
          salesCount: 1,
        });
      }),
    );
  });

  it('DENIES the whole transaction when no shift is open — an otherwise entirely valid sale, blocked purely '
    + 'by the missing shiftState/current, the real server-side enforcement of "open the day first"', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedProduct(BIZ, 'prod-1', 9);
    // No seedOpenShift() call.

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.set(doc(db, `businesses/${BIZ}/sales/sale-no-shift`), {
          receiptNumber: 'sale-no-shift',
          items: [],
          subtotal: 15000,
          total: 15000,
          method: 'cash',
          cashGiven: 15000,
          changeGiven: 0,
          customerId: null,
          customerName: null,
          staffId: 'attendant-uid',
          staffName: 'Attendant',
          createdAt: new Date().toISOString(),
        });
        transaction.update(doc(db, `businesses/${BIZ}/products/prod-1`), { stockCount: 8 });
      }),
    );

    await seed(async (adminDb) => {
      const saleSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/sales/sale-no-shift`));
      assert.equal(saleSnap.exists(), false); // never partially applied
      const productSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/products/prod-1`));
      assert.equal(productSnap.data().stockCount, 9); // untouched
    });
  });

  it('DENIES the whole transaction if a product line would take stockCount negative — the oversell guard', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedProduct(BIZ, 'prod-1', 1); // only 1 left
    await seedOpenShift(BIZ); // isolates the oversell guard as the cause, not shift-gating

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.set(doc(db, `businesses/${BIZ}/sales/sale-3`), {
          receiptNumber: 'sale-3',
          items: [],
          subtotal: 30000,
          total: 30000,
          method: 'cash',
          cashGiven: 30000,
          changeGiven: 0,
          customerId: null,
          customerName: null,
          staffId: 'attendant-uid',
          staffName: 'Attendant',
          createdAt: new Date().toISOString(),
        });
        // Two of the last one — would go to -1.
        transaction.update(doc(db, `businesses/${BIZ}/products/prod-1`), { stockCount: -1 });
      }),
    );

    // Never partially applied — the sale doc must not exist either.
    await seed(async (adminDb) => {
      const saleSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/sales/sale-3`));
      assert.equal(saleSnap.exists(), false);
      const productSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/products/prod-1`));
      assert.equal(productSnap.data().stockCount, 1); // untouched
    });
  });

  it(
    'DENIES the whole transaction if it tries to smuggle a non-stockCount product field through '
    + 'checkout — an attendant can never reprice while ringing up a sale, even bundled with a valid sale write',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedProduct(BIZ, 'prod-1', 9);
      await seedOpenShift(BIZ); // isolates the price-smuggling guard as the cause

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertFails(
        runTransaction(db, async (transaction) => {
          transaction.set(doc(db, `businesses/${BIZ}/sales/sale-4`), {
            receiptNumber: 'sale-4',
            items: [],
            subtotal: 15000,
            total: 15000,
            method: 'cash',
            cashGiven: 15000,
            changeGiven: 0,
            customerId: null,
            customerName: null,
            staffId: 'attendant-uid',
            staffName: 'Attendant',
            createdAt: new Date().toISOString(),
          });
          transaction.update(doc(db, `businesses/${BIZ}/products/prod-1`), {
            stockCount: 8,
            price: 1, // smuggled reprice
          });
        }),
      );

      await seed(async (adminDb) => {
        const productSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/products/prod-1`));
        assert.equal(productSnap.data().price, 15000); // untouched
      });
    },
  );

  it('DENIES the whole transaction for a staff member of a DIFFERENT business', async () => {
    await seedAttendant(OTHER_BIZ, 'attendant-uid');
    await seedProduct(BIZ, 'prod-1', 9);
    await seedOpenShift(BIZ); // isolates the cross-business guard as the cause

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.set(doc(db, `businesses/${BIZ}/sales/sale-5`), {
          receiptNumber: 'sale-5',
          items: [],
          subtotal: 15000,
          total: 15000,
          method: 'cash',
          cashGiven: 15000,
          changeGiven: 0,
          customerId: null,
          customerName: null,
          staffId: 'attendant-uid',
          staffName: 'Attendant',
          createdAt: new Date().toISOString(),
        });
        transaction.update(doc(db, `businesses/${BIZ}/products/prod-1`), { stockCount: 8 });
      }),
    );
  });

  it('DENIES an owner from also setting a product negative — the guard applies to owner writes too', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/staff/owner-uid`), {
        name: 'Owner',
        role: 'owner',
        active: true,
      });
    });
    await seedProduct(BIZ, 'prod-1', 1);

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(
      updateDoc(doc(db, `businesses/${BIZ}/products/prod-1`), { stockCount: -1 }),
    );
  });
});
