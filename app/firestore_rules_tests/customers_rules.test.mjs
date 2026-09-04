// Security-rules tests for /customers and its /transactions subcollection
// — customers moved from an in-memory fake to real Firestore this
// session, including a new create-customer flow. Run against the
// Firestore emulator (never the live project) — see
// invites_and_staff_rules.test.mjs for the emulator setup/run
// instructions, identical here.
//
// Covers: any active staff (not just owner) can create/read/write a
// customer — adding a walk-in mid credit-sale is an ordinary staff duty,
// not owner-only, unlike the catalog. The transaction subcollection is
// append-only (create-only, no update/delete), same shape as
// gasStockLedger. Includes a real multi-op transaction/batch shape, not
// isolated ops, per this session's invite-delete lesson.

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
import { doc, setDoc, getDoc, updateDoc, deleteDoc, writeBatch, runTransaction } from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BIZ = 'test-biz';
const OTHER_BIZ = 'other-biz';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-leumadepos-rules-test-customers',
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

async function seedCustomer(businessId, customerId, balance = 0) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/customers/${customerId}`), {
      name: 'Existing Customer',
      phone: '08000000000',
      balance,
    });
  });
}

function asUser(uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: true }).firestore();
}

describe('customers (/businesses/{businessId}/customers/{customerId})', () => {
  it('ALLOWS an active attendant (not just owner) to create a walk-in customer', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/customers/new-cust`), {
        name: 'Walk-in',
        phone: '08011112222',
        balance: 0,
      }),
    );
  });

  it('ALLOWS an active attendant to read a customer', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedCustomer(BIZ, 'cust-1', 5000);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(getDoc(doc(db, `businesses/${BIZ}/customers/cust-1`)));
  });

  it(
    'DENIES an active attendant from setting balance with a bare update — the actual fraud gap this '
    + 'closes: a staff member moving balance to any number with no paired, honest ledger entry',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedCustomer(BIZ, 'cust-1', 5000);

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertFails(updateDoc(doc(db, `businesses/${BIZ}/customers/cust-1`), { balance: 999999 }));
    },
  );

  it(
    'DENIES an active attendant from setting balance even WITH a lastTransactionId pointing at a '
    + 'ledger entry whose balanceAfter does not match — the pairing has to be honest, not just present',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedCustomer(BIZ, 'cust-1', 5000);

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertFails(
        runTransaction(db, async (transaction) => {
          transaction.update(doc(db, `businesses/${BIZ}/customers/cust-1`), {
            balance: 999999,
            lastTransactionId: 'fake-tx',
          });
          transaction.set(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/fake-tx`), {
            type: 'creditSale',
            amountNaira: 1,
            balanceAfter: 5001, // does not match the balance being written above
            createdAt: new Date().toISOString(),
            saleId: null,
          });
        }),
      );
    },
  );

  it(
    'ALLOWS an active attendant to move balance when paired with a matching ledger entry in the same '
    + 'transaction — the real recordCreditSale/recordRepayment shape',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedCustomer(BIZ, 'cust-1', 5000);

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertSucceeds(
        runTransaction(db, async (transaction) => {
          transaction.update(doc(db, `businesses/${BIZ}/customers/cust-1`), {
            balance: 9000,
            lastTransactionId: 'tx-real',
          });
          transaction.set(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-real`), {
            type: 'creditSale',
            amountNaira: 4000,
            balanceAfter: 9000,
            createdAt: new Date().toISOString(),
            saleId: 'sale-1',
          });
        }),
      );
    },
  );

  it('DENIES an active attendant from creating a customer with a nonzero opening balance', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/customers/new-cust`), {
        name: 'Migrated Debtor',
        phone: '08011112222',
        balance: 15000,
      }),
    );
  });

  it(
    'ALLOWS an active owner to create a customer with a nonzero opening balance — migrating an '
    + 'existing debtor',
    async () => {
      await seed(async (db) => {
        await setDoc(doc(db, `businesses/${BIZ}/staff/owner-uid`), {
          name: 'Owner',
          role: 'owner',
          active: true,
        });
      });
      const db = asUser('owner-uid', 'owner@example.com');
      await assertSucceeds(
        setDoc(doc(db, `businesses/${BIZ}/customers/new-cust`), {
          name: 'Migrated Debtor',
          phone: '08011112222',
          balance: 15000,
        }),
      );
    },
  );

  it('ALLOWS an active owner to update a customer\'s name/phone freely, without any ledger pairing', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/staff/owner-uid`), {
        name: 'Owner',
        role: 'owner',
        active: true,
      });
    });
    await seedCustomer(BIZ, 'cust-1', 5000);

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(updateDoc(doc(db, `businesses/${BIZ}/customers/cust-1`), { name: 'Renamed' }));
  });

  it('DENIES an unauthenticated request from reading, creating, or writing a customer', async () => {
    await seedCustomer(BIZ, 'cust-1');
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/customers/cust-1`)));
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/customers/new-cust`), { name: 'X', phone: 'Y', balance: 0 }));
  });

  it('DENIES an active staff member of a DIFFERENT business from touching this business\'s customers', async () => {
    await seedAttendant(OTHER_BIZ, 'attendant-uid');
    await seedCustomer(BIZ, 'cust-1');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/customers/cust-1`)));
    await assertFails(updateDoc(doc(db, `businesses/${BIZ}/customers/cust-1`), { balance: 1 }));
  });
});

describe('customer transactions (/businesses/{businessId}/customers/{customerId}/transactions/{id})', () => {
  it('ALLOWS an active attendant to create a transaction entry', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedCustomer(BIZ, 'cust-1');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-1`), {
        type: 'creditSale',
        amountNaira: 4000,
        balanceAfter: 4000,
        createdAt: new Date().toISOString(),
        saleId: 'sale-1',
      }),
    );
  });

  it('DENIES updating or deleting a transaction entry — append-only, same as gasStockLedger', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedCustomer(BIZ, 'cust-1');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-1`), {
        type: 'creditSale',
        amountNaira: 4000,
        balanceAfter: 4000,
        createdAt: new Date().toISOString(),
        saleId: 'sale-1',
      });
    });

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(updateDoc(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-1`), { amountNaira: 1 }));
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-1`)));
  });

  it(
    'ALLOWS the real multi-op write a credit sale performs — customer balance update + '
    + 'transaction-ledger create, together, as one batch',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedCustomer(BIZ, 'cust-1', 2000);

      const db = asUser('attendant-uid', 'attendant@example.com');
      const batch = writeBatch(db);
      batch.update(doc(db, `businesses/${BIZ}/customers/cust-1`), {
        balance: 6000,
        lastTransactionId: 'tx-2',
      });
      batch.set(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-2`), {
        type: 'creditSale',
        amountNaira: 4000,
        balanceAfter: 6000,
        createdAt: new Date().toISOString(),
        saleId: 'sale-2',
      });
      await assertSucceeds(batch.commit());
    },
  );

  it('DENIES an unauthenticated request from creating a transaction entry', async () => {
    await seedCustomer(BIZ, 'cust-1');
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/customers/cust-1/transactions/tx-1`), {
        type: 'creditSale',
        amountNaira: 1,
        balanceAfter: 1,
        createdAt: new Date().toISOString(),
        saleId: null,
      }),
    );
  });
});
