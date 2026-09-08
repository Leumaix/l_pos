// Security-rules tests for the split-tender + cash-change feature —
// Phase 3 of that work (see the design doc discussed in-session; Phase 0
// was the standalone customers/{customerId} replay-hole fix, Phase 1 the
// Dart domain layer, Phase 2 the data-layer cascade).
//
// checkout_commit_rules.test.mjs already covers the full realistic
// checkout transaction (sale + shiftState totals, including split-tender
// and overpay-with-change cases, and the shiftState/lastSaleId pairing +
// anti-replay checks). This file is scoped to what that one doesn't
// dedicate coverage to:
//   1. The customers/{customerId}/transactions/{id} creditSale-specific
//      cross-check — real sale-backed amounts, the anti-replay check on
//      ITS OWN saleId (distinct from shiftState's lastSaleId), and a
//      split sale where only PART of the total is charged to the
//      customer (not sale.total).
//   2. The worked numeric example from the design doc's own §2, run as
//      three real, sequential transactions against a real shift — proof
//      that expectedCashNaira's existing, UNCHANGED formula
//      (openingFloatNaira + cashTotalNaira) already produces the right
//      answer for cross-method change, with no formula change needed.
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
import { doc, setDoc, getDoc, runTransaction } from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BIZ = 'test-biz';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-leumadepos-rules-test-split-tender',
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

describe('customers/{customerId}/transactions — creditSale cross-check against the real sale', () => {
  it(
    'ALLOWS a creditSale entry for a SPLIT sale where only PART of the total was charged to the '
    + 'customer — the exact case that needed creditLineAmount instead of sale.total',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedCustomer(BIZ, 'cust-1', 0);
      await seedOpenShift(BIZ);

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertSucceeds(
        runTransaction(db, async (transaction) => {
          transaction.set(
            doc(db, `businesses/${BIZ}/sales/sale-split-credit`),
            baseSale({
              receiptNumber: 'sale-split-credit',
              total: 15000,
              payments: [
                { method: 'customerAccount', amountNaira: 5000, customerId: 'cust-1', customerName: 'Ngozi Eze' },
                { method: 'cash', amountNaira: 10000 },
              ],
            }),
          );
          transaction.update(doc(db, `businesses/${BIZ}/customers/cust-1`), {
            balance: 5000, // 0 + 5000, NOT 0 + 15000 (sale.total)
            lastTransactionId: 'tx-split',
          });
          transaction.set(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-split`), {
            type: 'creditSale',
            amountNaira: 5000, // the credit LINE's amount, not sale.total
            balanceAfter: 5000,
            createdAt: new Date().toISOString(),
            saleId: 'sale-split-credit',
          });
          transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
            creditTotalNaira: 5000,
            cashTotalNaira: 10000,
            salesCount: 1,
            lastSaleId: 'sale-split-credit',
          });
        }),
      );
    },
  );

  it(
    'DENIES a creditSale entry claiming MORE than the sale\'s own customerAccount line for this '
    + 'customer — a real ₦5,000 credit line paired with a fabricated ₦50,000 ledger entry',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedCustomer(BIZ, 'cust-1', 0);

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertFails(
        runTransaction(db, async (transaction) => {
          transaction.set(
            doc(db, `businesses/${BIZ}/sales/sale-fake-amount`),
            baseSale({
              receiptNumber: 'sale-fake-amount',
              total: 15000,
              payments: [
                { method: 'customerAccount', amountNaira: 5000, customerId: 'cust-1', customerName: 'Ngozi Eze' },
                { method: 'cash', amountNaira: 10000 },
              ],
            }),
          );
          transaction.update(doc(db, `businesses/${BIZ}/customers/cust-1`), {
            balance: 50000,
            lastTransactionId: 'tx-fake',
          });
          transaction.set(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-fake`), {
            type: 'creditSale',
            amountNaira: 50000, // does not match the sale's real 5000 line
            balanceAfter: 50000,
            createdAt: new Date().toISOString(),
            saleId: 'sale-fake-amount',
          });
        }),
      );
    },
  );

  it(
    'DENIES a creditSale entry for a customer the sale\'s customerAccount line does not actually name '
    + '— the credit line belongs to a different customer entirely',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedCustomer(BIZ, 'cust-1', 0);
      await seedCustomer(BIZ, 'cust-2', 0);

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertFails(
        runTransaction(db, async (transaction) => {
          transaction.set(
            doc(db, `businesses/${BIZ}/sales/sale-wrong-customer`),
            baseSale({
              receiptNumber: 'sale-wrong-customer',
              total: 5000,
              payments: [
                { method: 'customerAccount', amountNaira: 5000, customerId: 'cust-1', customerName: 'Ngozi Eze' },
              ],
            }),
          );
          // Charges cust-2 instead — the sale's own line names cust-1.
          transaction.update(doc(db, `businesses/${BIZ}/customers/cust-2`), {
            balance: 5000,
            lastTransactionId: 'tx-wrong',
          });
          transaction.set(doc(db, `businesses/${BIZ}/customers/cust-2/transactions/tx-wrong`), {
            type: 'creditSale',
            amountNaira: 5000,
            balanceAfter: 5000,
            createdAt: new Date().toISOString(),
            saleId: 'sale-wrong-customer',
          });
        }),
      );
    },
  );

  it(
    'DENIES a creditSale entry whose balanceAfter does not arithmetically follow from the pre-write '
    + 'balance plus its own amountNaira — even when amountNaira itself correctly matches the sale',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedCustomer(BIZ, 'cust-1', 2000);

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertFails(
        runTransaction(db, async (transaction) => {
          transaction.set(
            doc(db, `businesses/${BIZ}/sales/sale-fake-balance`),
            baseSale({
              receiptNumber: 'sale-fake-balance',
              total: 5000,
              payments: [
                { method: 'customerAccount', amountNaira: 5000, customerId: 'cust-1', customerName: 'Ngozi Eze' },
              ],
            }),
          );
          transaction.update(doc(db, `businesses/${BIZ}/customers/cust-1`), {
            balance: 999999, // should be 2000 + 5000 = 7000
            lastTransactionId: 'tx-bad-balance',
          });
          transaction.set(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-bad-balance`), {
            type: 'creditSale',
            amountNaira: 5000, // correctly matches the sale's line
            balanceAfter: 999999, // but the arithmetic is fabricated
            createdAt: new Date().toISOString(),
            saleId: 'sale-fake-balance',
          });
        }),
      );
    },
  );

  it(
    'DENIES a creditSale entry whose saleId points at an OLD, already-existing sale — the same '
    + 'anti-replay reasoning as shiftState\'s lastSaleId, applied to this rule\'s own saleId reference',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedCustomer(BIZ, 'cust-1', 0);
      await seed(async (db) => {
        await setDoc(
          doc(db, `businesses/${BIZ}/sales/old-sale`),
          baseSale({
            receiptNumber: 'old-sale',
            total: 5000,
            payments: [
              { method: 'customerAccount', amountNaira: 5000, customerId: 'cust-1', customerName: 'Ngozi Eze' },
            ],
          }),
        );
      });

      const db = asUser('attendant-uid', 'attendant@example.com');
      // No new sale created in this write — reuses old-sale's id and its
      // already-true 5000 credit line to justify a fresh balance change.
      await assertFails(
        runTransaction(db, async (transaction) => {
          transaction.update(doc(db, `businesses/${BIZ}/customers/cust-1`), {
            balance: 5000,
            lastTransactionId: 'tx-replay',
          });
          transaction.set(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-replay`), {
            type: 'creditSale',
            amountNaira: 5000,
            balanceAfter: 5000,
            createdAt: new Date().toISOString(),
            saleId: 'old-sale',
          });
        }),
      );
    },
  );

  it(
    'ALLOWS a repayment entry untouched by any of this — no sale to check against, same as before '
    + 'this phase',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedCustomer(BIZ, 'cust-1', 5000);

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertSucceeds(
        runTransaction(db, async (transaction) => {
          transaction.update(doc(db, `businesses/${BIZ}/customers/cust-1`), {
            balance: 2000,
            lastTransactionId: 'tx-repay',
          });
          transaction.set(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-repay`), {
            type: 'repayment',
            amountNaira: 3000,
            balanceAfter: 2000,
            createdAt: new Date().toISOString(),
            saleId: null,
          });
        }),
      );
    },
  );
});

describe('the worked numeric example (design doc §2) — real transactions, real numbers', () => {
  it(
    'produces expectedCashNaira = 13,000 for a shift with a cash sale, a transfer-overpay-with-cash-'
    + 'change sale, and a card+cash split sale — using shiftState.expectedCashNaira\'s EXISTING, '
    + 'UNCHANGED formula (openingFloatNaira + cashTotalNaira), no new field, no formula change',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedOpenShift(BIZ, { openingFloatNaira: 10000 });
      const db = asUser('attendant-uid', 'attendant@example.com');

      // Sale A — cash, exact: total 2,000.
      await assertSucceeds(
        runTransaction(db, async (transaction) => {
          transaction.set(
            doc(db, `businesses/${BIZ}/sales/sale-a`),
            baseSale({ receiptNumber: 'sale-a', total: 2000, payments: [{ method: 'cash', amountNaira: 2000 }] }),
          );
          transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
            cashTotalNaira: 2000,
            salesCount: 1,
            lastSaleId: 'sale-a',
          });
        }),
      );

      // Sale B — transfer overpaid, cash change: total 4,500, customer
      // transfers 5,000, shop hands back 500 cash.
      await assertSucceeds(
        runTransaction(db, async (transaction) => {
          transaction.set(
            doc(db, `businesses/${BIZ}/sales/sale-b`),
            baseSale({
              receiptNumber: 'sale-b',
              total: 4500,
              payments: [
                { method: 'transfer', amountNaira: 5000 },
                { method: 'cash', amountNaira: -500 },
              ],
            }),
          );
          transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
            transferTotalNaira: 5000,
            cashTotalNaira: 1500, // 2000 (from A) + (-500)
            salesCount: 2,
            lastSaleId: 'sale-b',
          });
        }),
      );

      // Sale C — split, no change: total 4,500, ₦3,000 card + ₦1,500 cash.
      await assertSucceeds(
        runTransaction(db, async (transaction) => {
          transaction.set(
            doc(db, `businesses/${BIZ}/sales/sale-c`),
            baseSale({
              receiptNumber: 'sale-c',
              total: 4500,
              payments: [
                { method: 'card', amountNaira: 3000 },
                { method: 'cash', amountNaira: 1500 },
              ],
            }),
          );
          transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
            cardTotalNaira: 3000,
            cashTotalNaira: 3000, // 1500 (running) + 1500
            salesCount: 3,
            lastSaleId: 'sale-c',
          });
        }),
      );

      await seed(async (adminDb) => {
        const shiftSnap = await getDoc(doc(adminDb, `businesses/${BIZ}/shiftState/current`));
        const shift = shiftSnap.data();
        assert.equal(shift.cashTotalNaira, 3000);
        assert.equal(shift.cardTotalNaira, 3000);
        assert.equal(shift.transferTotalNaira, 5000);
        assert.equal(shift.creditTotalNaira, 0);
        assert.equal(shift.salesCount, 3);

        // OpenShift.expectedCashNaira's own formula, unchanged — see
        // shift.dart. Matches the physical drawer trace exactly: 10000
        // -> +2000 (A) -> -500 (B's change) -> +1500 (C) = 13000.
        const expectedCashNaira = shift.openingFloatNaira + shift.cashTotalNaira;
        assert.equal(expectedCashNaira, 13000);
      });
    },
  );
});
