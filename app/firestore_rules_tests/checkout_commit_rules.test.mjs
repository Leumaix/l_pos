// Security-rules tests for the atomic checkout commit — the real
// Firestore transaction FirebaseCheckoutRepository.commitSale performs
// (sale record + gas stock/ledger + product stockCount decrements +
// customer balance/transaction + shift totals), exercised as ONE real
// transaction, not isolated single-document writes. This is the same
// lesson this session's invite-delete bug taught: a rule can allow every
// operation individually and still deny (or wrongly allow) the combined
// write — only testing the real shape catches that.
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

// A bare sale doc — receiptNumber/items/staff fields any real checkout
// write would include, minus `total`/`payments`, which every call site
// below fills in for its own scenario.
function baseSale(overrides) {
  return {
    receiptNumber: overrides.receiptNumber ?? 'sale',
    items: [],
    subtotal: overrides.total,
    staffId: 'attendant-uid',
    staffName: 'Attendant',
    createdAt: new Date().toISOString(),
    ...overrides,
  };
}

describe('checkout commit — the real transaction FirebaseCheckoutRepository.commitSale performs', () => {
  it('ALLOWS a cash sale (sale record + product stockCount decrement + shift totals increment) as one transaction', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedProduct(BIZ, 'prod-1', 9);
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        transaction.set(
          doc(db, `businesses/${BIZ}/sales/sale-1`),
          baseSale({
            receiptNumber: 'sale-1',
            total: 15000,
            payments: [{ method: 'cash', amountNaira: 15000 }],
          }),
        );
        transaction.update(doc(db, `businesses/${BIZ}/products/prod-1`), { stockCount: 8 });
        // The shift-time totals write FirebaseCheckoutRepository.commitSale
        // now performs alongside every other mutation in this one
        // transaction — see FirebaseInventoryRepository/checkout's doc
        // comments and shift_rules.test.mjs for shiftState/current's own
        // rules coverage.
        transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
          cashTotalNaira: 15000,
          salesCount: 1,
          lastSaleId: 'sale-1',
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
        transaction.set(
          doc(db, `businesses/${BIZ}/sales/sale-2`),
          baseSale({
            receiptNumber: 'sale-2',
            total: 22000,
            payments: [
              { method: 'customerAccount', amountNaira: 22000, customerId: 'cust-1', customerName: 'Ngozi Eze' },
            ],
          }),
        );
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
          lastSaleId: 'sale-2',
        });
      }),
    );
  });

  it('ALLOWS a split-tender sale — card + cash, no change — the new capability this phase adds', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        transaction.set(
          doc(db, `businesses/${BIZ}/sales/sale-split`),
          baseSale({
            receiptNumber: 'sale-split',
            total: 15000,
            payments: [
              { method: 'card', amountNaira: 10000 },
              { method: 'cash', amountNaira: 5000 },
            ],
          }),
        );
        transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
          cardTotalNaira: 10000,
          cashTotalNaira: 5000,
          salesCount: 1,
          lastSaleId: 'sale-split',
        });
      }),
    );

    await seed(async (adminDb) => {
      const shiftSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/shiftState/current`));
      assert.equal(shiftSnap.data().cardTotalNaira, 10000);
      assert.equal(shiftSnap.data().cashTotalNaira, 5000);
    });
  });

  it(
    'ALLOWS overpay-by-transfer with cash change — the exact new scenario this feature adds: '
    + 'a negative cash line nets correctly against cashTotalNaira with no separate field needed',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedOpenShift(BIZ, { cashTotalNaira: 2000 }); // some cash already in the drawer this shift

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertSucceeds(
        runTransaction(db, async (transaction) => {
          transaction.set(
            doc(db, `businesses/${BIZ}/sales/sale-change`),
            baseSale({
              receiptNumber: 'sale-change',
              total: 15000,
              payments: [
                { method: 'transfer', amountNaira: 20000 },
                { method: 'cash', amountNaira: -5000 },
              ],
            }),
          );
          transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
            transferTotalNaira: 20000,
            cashTotalNaira: -3000, // resulting absolute value: 2000 (seeded) + (-5000) delta
            salesCount: 1,
            lastSaleId: 'sale-change',
          });
        }),
      );

      await seed(async (adminDb) => {
        const shiftSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/shiftState/current`));
        assert.equal(shiftSnap.data().transferTotalNaira, 20000);
        // 2000 (already there) + (-5000 increment) = -3000, correctly
        // negative — this shift gave out more cash as change than it
        // took in as cash sales, a real signal, not a bug.
        assert.equal(shiftSnap.data().cashTotalNaira, -3000);
      });
    },
  );

  it('DENIES the whole transaction when the payments don\'t sum to the total', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.set(
          doc(db, `businesses/${BIZ}/sales/sale-bad-sum`),
          baseSale({
            receiptNumber: 'sale-bad-sum',
            total: 15000,
            payments: [{ method: 'cash', amountNaira: 10000 }], // short by 5000
          }),
        );
        transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
          cashTotalNaira: 10000,
          salesCount: 1,
          lastSaleId: 'sale-bad-sum',
        });
      }),
    );
  });

  it('DENIES the whole transaction for a negative card line — only cash may ever be negative', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.set(
          doc(db, `businesses/${BIZ}/sales/sale-bad-neg`),
          baseSale({
            receiptNumber: 'sale-bad-neg',
            total: 15000,
            payments: [
              { method: 'transfer', amountNaira: 20000 },
              { method: 'card', amountNaira: -5000 }, // change must be cash
            ],
          }),
        );
        transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
          transferTotalNaira: 20000,
          cardTotalNaira: -5000,
          salesCount: 1,
          lastSaleId: 'sale-bad-neg',
        });
      }),
    );
  });

  it('DENIES the whole transaction for two customerAccount lines', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedCustomer(BIZ, 'cust-1', 0);
    await seedCustomer(BIZ, 'cust-2', 0);
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.set(
          doc(db, `businesses/${BIZ}/sales/sale-two-credit`),
          baseSale({
            receiptNumber: 'sale-two-credit',
            total: 15000,
            payments: [
              { method: 'customerAccount', amountNaira: 10000, customerId: 'cust-1', customerName: 'A' },
              { method: 'customerAccount', amountNaira: 5000, customerId: 'cust-2', customerName: 'B' },
            ],
          }),
        );
        transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
          creditTotalNaira: 15000,
          salesCount: 1,
          lastSaleId: 'sale-two-credit',
        });
      }),
    );
  });

  it('DENIES the whole transaction with more than 4 payment lines — the kMaxPaymentLines cap', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.set(
          doc(db, `businesses/${BIZ}/sales/sale-too-many`),
          baseSale({
            receiptNumber: 'sale-too-many',
            total: 15000,
            payments: [
              { method: 'cash', amountNaira: 3000 },
              { method: 'card', amountNaira: 3000 },
              { method: 'transfer', amountNaira: 3000 },
              { method: 'cash', amountNaira: 3000 },
              { method: 'cash', amountNaira: 3000 },
            ],
          }),
        );
        transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
          cashTotalNaira: 9000,
          cardTotalNaira: 3000,
          transferTotalNaira: 3000,
          salesCount: 1,
          lastSaleId: 'sale-too-many',
        });
      }),
    );
  });

  it(
    'ALLOWS a self-consistent but fictionally large change line — documenting the residual risk, not '
    + 'a gap this phase claims to close: a sale claiming a ₦54,500 transfer and ₦50,000 cash change is '
    + 'internally self-consistent (sums to the claimed total, shiftState matches the sale), so it is NOT '
    + 'rejected — the same accepted boundary as sale.total never being checked against real cart '
    + 'contents. What IS closed is shiftState disagreeing with its own paired sale — see the next test.',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedOpenShift(BIZ, { cashTotalNaira: 50000 });

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertSucceeds(
        runTransaction(db, async (transaction) => {
          transaction.set(
            doc(db, `businesses/${BIZ}/sales/sale-siphon`),
            baseSale({
              receiptNumber: 'sale-siphon',
              total: 4500,
              payments: [
                { method: 'transfer', amountNaira: 54500 },
                { method: 'cash', amountNaira: -50000 },
              ],
            }),
          );
          transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
            transferTotalNaira: 54500,
            cashTotalNaira: 0, // resulting absolute value: 50000 (seeded) + (-50000) delta
            salesCount: 1,
            lastSaleId: 'sale-siphon',
          });
        }),
      );
    },
  );

  it(
    'DENIES the whole transaction when shiftState claims a DIFFERENT cash decrement than the paired '
    + 'sale actually records — shiftState and the sale can no longer just agree with each other on a '
    + 'fabricated number without the sale itself backing it up',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedOpenShift(BIZ, { cashTotalNaira: 50000, transferTotalNaira: 0 });

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertFails(
        runTransaction(db, async (transaction) => {
          // A real, honestly small sale...
          transaction.set(
            doc(db, `businesses/${BIZ}/sales/sale-mismatch`),
            baseSale({
              receiptNumber: 'sale-mismatch',
              total: 4500,
              payments: [
                { method: 'transfer', amountNaira: 5000 },
                { method: 'cash', amountNaira: -500 },
              ],
            }),
          );
          // ...paired with a shiftState update that claims a much
          // bigger cash outflow than that sale actually says.
          transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
            transferTotalNaira: 5000,
            cashTotalNaira: -45000,
            salesCount: 1,
            lastSaleId: 'sale-mismatch',
          });
        }),
      );
    },
  );

  it(
    'DENIES the whole transaction when lastSaleId points at an OLD, already-existing sale — the '
    + 'anti-replay check: a genuinely new totals change has to be paired with a genuinely new sale, '
    + 'not one reused to "prove" a fresh change',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      // A real, honest sale from earlier.
      await seed(async (db) => {
        await setDoc(
          doc(db, `businesses/${BIZ}/sales/old-sale`),
          baseSale({
            receiptNumber: 'old-sale',
            total: 5000,
            payments: [{ method: 'cash', amountNaira: 5000 }],
          }),
        );
      });
      await seedOpenShift(BIZ);

      const db = asUser('attendant-uid', 'attendant@example.com');
      // A bare shiftState update — no new sale created in this write —
      // that reuses old-sale's id and its already-true totals to "prove"
      // a fresh change with nothing new actually recorded.
      await assertFails(
        updateDoc(doc(db, `businesses/${BIZ}/shiftState/current`), {
          cashTotalNaira: 5000,
          salesCount: 1,
          lastSaleId: 'old-sale',
        }),
      );
    },
  );

  it('DENIES the whole transaction when no shift is open — an otherwise entirely valid sale, blocked purely '
    + 'by the missing shiftState/current, the real server-side enforcement of "open the day first"', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedProduct(BIZ, 'prod-1', 9);
    // No seedOpenShift() call.

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.set(
          doc(db, `businesses/${BIZ}/sales/sale-no-shift`),
          baseSale({
            receiptNumber: 'sale-no-shift',
            total: 15000,
            payments: [{ method: 'cash', amountNaira: 15000 }],
          }),
        );
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
        transaction.set(
          doc(db, `businesses/${BIZ}/sales/sale-3`),
          baseSale({
            receiptNumber: 'sale-3',
            total: 30000,
            payments: [{ method: 'cash', amountNaira: 30000 }],
          }),
        );
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
          transaction.set(
            doc(db, `businesses/${BIZ}/sales/sale-4`),
            baseSale({
              receiptNumber: 'sale-4',
              total: 15000,
              payments: [{ method: 'cash', amountNaira: 15000 }],
            }),
          );
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
        transaction.set(
          doc(db, `businesses/${BIZ}/sales/sale-5`),
          baseSale({
            receiptNumber: 'sale-5',
            total: 15000,
            payments: [{ method: 'cash', amountNaira: 15000 }],
          }),
        );
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
