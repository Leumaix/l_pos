// Security-rules tests for the owner-managed catalog (categories +
// products). Run against the Firestore emulator (never the live
// project) — see invites_and_staff_rules.test.mjs for setup/run
// instructions, identical here.
//
// Covers: only an active owner can create/update/delete a category or a
// product; an active (non-owner) staff member can still update a
// product's stockCount ONLY (sell/restock) but nothing else, and can't
// create or delete either kind of document; nobody can reach another
// business's catalog.

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
    // runner may run files concurrently against one shared emulator.
    projectId: 'demo-leumadepos-rules-test-catalog',
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

describe('categories (/businesses/{businessId}/categories/{categoryId})', () => {
  it('ALLOWS an active owner to create a category', async () => {
    await seedOwner(BIZ, 'owner-uid');
    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(setDoc(doc(db, `businesses/${BIZ}/categories/cat1`), { name: 'Cylinders', sortOrder: 0 }));
  });

  it('DENIES a non-owner (active attendant) from creating a category', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/categories/cat1`), { name: 'Cylinders', sortOrder: 0 }));
  });

  it('DENIES an unauthenticated request from creating a category', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/categories/cat1`), { name: 'Cylinders', sortOrder: 0 }));
  });

  it('ALLOWS an active owner to rename (update) a category', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/categories/cat1`), { name: 'Cylinders', sortOrder: 0 });
    });
    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(setDoc(doc(db, `businesses/${BIZ}/categories/cat1`), { name: 'Gas Cylinders', sortOrder: 0 }));
  });

  it('DENIES a non-owner from renaming a category', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/categories/cat1`), { name: 'Cylinders', sortOrder: 0 });
    });
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/categories/cat1`), { name: 'Hacked', sortOrder: 0 }));
  });

  it('ALLOWS an active owner to delete a category', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/categories/cat1`), { name: 'Cylinders', sortOrder: 0 });
    });
    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(deleteDoc(doc(db, `businesses/${BIZ}/categories/cat1`)));
  });

  it('DENIES a non-owner from deleting a category', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/categories/cat1`), { name: 'Cylinders', sortOrder: 0 });
    });
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/categories/cat1`)));
  });

  it('DENIES an owner from writing into a DIFFERENT business\'s categories', async () => {
    await seedOwner(BIZ, 'owner-uid'); // owner of BIZ, not OTHER_BIZ
    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${OTHER_BIZ}/categories/cat1`), { name: 'Snuck In', sortOrder: 0 }),
    );
  });
});

describe('products (/businesses/{businessId}/products/{productId})', () => {
  const fullProduct = {
    categoryId: 'cat1',
    name: '3kg Cylinder',
    price: 8000,
    stockCount: 12,
    unit: 'piece',
  };

  it('ALLOWS an active owner to create a product', async () => {
    await seedOwner(BIZ, 'owner-uid');
    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(setDoc(doc(db, `businesses/${BIZ}/products/p1`), fullProduct));
  });

  it('DENIES a non-owner (active attendant) from creating a product', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/products/p1`), fullProduct));
  });

  it('DENIES an unauthenticated request from creating a product', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/products/p1`), fullProduct));
  });

  it('ALLOWS an active owner to change ANY field on a product (rename/reprice/move/restock)', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/products/p1`), fullProduct);
    });
    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/products/p1`), {
        ...fullProduct,
        name: 'Renamed',
        price: 9000,
        categoryId: 'cat2',
        stockCount: 20,
      }),
    );
  });

  it('ALLOWS an active staff member to update ONLY stockCount (a sale or a restock)', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/products/p1`), fullProduct);
    });
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/products/p1`), { ...fullProduct, stockCount: 11 }),
    );
  });

  it('DENIES an active staff member from changing name/price/categoryId/unit, even alongside stockCount', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/products/p1`), fullProduct);
    });
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/products/p1`), {
        ...fullProduct,
        stockCount: 11,
        price: 1, // sneaking a reprice in alongside the legitimate stock move
      }),
    );
  });

  it('DENIES an active staff member from creating a product', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/products/p1`), fullProduct));
  });

  it('DENIES an active staff member from deleting a product', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/products/p1`), fullProduct);
    });
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/products/p1`)));
  });

  it('ALLOWS an active owner to delete a product', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/products/p1`), fullProduct);
    });
    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(deleteDoc(doc(db, `businesses/${BIZ}/products/p1`)));
  });

  it('DENIES writing into a DIFFERENT business\'s products, even as an active owner of one\'s own', async () => {
    await seedOwner(BIZ, 'owner-uid'); // owner of BIZ, not OTHER_BIZ
    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(setDoc(doc(db, `businesses/${OTHER_BIZ}/products/p1`), fullProduct));
  });

  it('DENIES a staff member of one business from touching another business\'s product stock', async () => {
    await seedAttendant(BIZ, 'attendant-uid'); // staff of BIZ, not OTHER_BIZ
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${OTHER_BIZ}/products/p1`), fullProduct);
    });
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${OTHER_BIZ}/products/p1`), { ...fullProduct, stockCount: 0 }),
    );
  });
});
