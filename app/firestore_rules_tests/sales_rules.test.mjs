// Security-rules tests for /sales read/write access.
// Run against the Firestore emulator (never the live project) — see
// invites_and_staff_rules.test.mjs for the emulator setup/run
// instructions, identical here.
//
// Covers: read is owner-only (revenue is business-wide financial data an
// attendant isn't shown by design — see Home's owner/attendant split);
// create stays open to any active staff member (checkout writes a sale
// regardless of role); update/delete are denied for everyone, always —
// a sale is immutable once recorded.

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
    // Distinct project ID from the other rules test files — Node's test
    // runner may run files concurrently, and they all share one running
    // emulator; separate projects keep clearFirestore() calls from
    // racing each other.
    projectId: 'demo-leumadepos-rules-test-sales',
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

async function seedSale(businessId, saleId) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/sales/${saleId}`), {
      totalNaira: 45000,
      createdAt: new Date().toISOString(),
    });
  });
}

function asUser(uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: true }).firestore();
}

describe('sales (/businesses/{businessId}/sales/{saleId})', () => {
  it('ALLOWS an active owner to read a sale', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedSale(BIZ, 'sale-1');

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(getDoc(doc(db, `businesses/${BIZ}/sales/sale-1`)));
  });

  it('DENIES an active attendant from reading a sale — the actual gap this rule closes: '
    + 'an attendant is not shown revenue in the UI, but without this their own authenticated '
    + 'session could otherwise query full revenue directly, bypassing that entirely', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedSale(BIZ, 'sale-1');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/sales/sale-1`)));
  });

  it('DENIES an unauthenticated request from reading a sale', async () => {
    await seedSale(BIZ, 'sale-1');

    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/sales/sale-1`)));
  });

  it('DENIES an active owner of a DIFFERENT business from reading this business\'s sale', async () => {
    await seedOwner(OTHER_BIZ, 'owner-uid');
    await seedSale(BIZ, 'sale-1');

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/sales/sale-1`)));
  });

  it('ALLOWS an active attendant to create a sale (checkout works regardless of role)', async () => {
    await seedAttendant(BIZ, 'attendant-uid');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/sales/sale-2`), {
        totalNaira: 12000,
        createdAt: new Date().toISOString(),
      }),
    );
  });

  it('ALLOWS an active owner to create a sale too', async () => {
    await seedOwner(BIZ, 'owner-uid');

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/sales/sale-3`), {
        totalNaira: 8000,
        createdAt: new Date().toISOString(),
      }),
    );
  });

  it('DENIES anyone, including the owner, from updating a recorded sale — immutable once written', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedSale(BIZ, 'sale-1');

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/sales/sale-1`), { totalNaira: 99999 }, { merge: true }));
  });

  it('DENIES anyone, including the owner, from deleting a recorded sale', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedSale(BIZ, 'sale-1');

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/sales/sale-1`)));
  });
});
