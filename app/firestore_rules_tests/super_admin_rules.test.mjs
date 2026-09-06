// Security-rules tests for the platform super-admin (the separate
// onboarding tool used by Sammy alone) — run against the Firestore
// emulator (never the live project); see invites_and_staff_rules.test.mjs
// for the emulator setup/run instructions, identical here.
//
// This is deliberately its own file rather than folded into
// business_settings_rules.test.mjs or invites_and_staff_rules.test.mjs:
// super-admin's read access cuts across every collection in the file, so
// its BOUNDARY — everything it's still denied — doesn't belong to any one
// existing feature's test file. (Those two files each also carry one
// direct, local positive-control test for the specific rule they extend;
// this file is the comprehensive proof of the whole carve-out, including
// everywhere it's NOT supposed to reach.)
//
// Covers:
//   1. super-admin CAN create a new business, and the first-owner invite
//      for a business with zero staff docs — the two carve-outs that
//      exist for it.
//   2. super-admin CAN read across every collection on a business it has
//      no staff doc in at all — the monitoring capability.
//   3. super-admin CANNOT write/update/delete a single thing in any
//      business's actual operational data (sales, customers, gas stock,
//      products, shift state) — read-only really means read-only.
//   4. super-admin CANNOT update an existing business's own document
//      (name/settings) — that stays owner-only, unchanged.
//   5. platformConfig/superAdmins itself is unreadable and unwritable by
//      any client, even a recognized super-admin.

import { before, after, beforeEach, describe, it } from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, getDocs, deleteDoc, collection } from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// A business the super-admin is deliberately NOT staff of — every read
// test in this file proves cross-business access on THIS business, not
// one it happens to belong to.
const BIZ = 'other-owners-biz';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    // Distinct project ID — Node's test runner may run files concurrently
    // against the one running emulator; separate projects keep each
    // file's clearFirestore() from racing the others.
    projectId: 'demo-leumadepos-rules-test-superadmin',
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

/** Seeds Firestore state directly, bypassing security rules entirely. */
async function seed(setupFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setupFn(context.firestore());
  });
}

async function seedSuperAdmin(uid) {
  await seed(async (db) => {
    await setDoc(doc(db, 'platformConfig/superAdmins'), { uids: [uid] });
  });
}

async function seedOwner(businessId, uid) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/staff/${uid}`), {
      name: 'Real Owner',
      role: 'owner',
      active: true,
    });
  });
}

function asUser(uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: true }).firestore();
}

const ADMIN_UID = 'super-admin-uid';
const ADMIN_EMAIL = 'admin@example.com';

describe('super-admin — the two carve-outs it actually has', () => {
  it('ALLOWS creating a brand-new business document', async () => {
    await seedSuperAdmin(ADMIN_UID);
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertSucceeds(setDoc(doc(db, 'businesses/fresh-biz'), { name: 'Fresh Biz' }));
  });

  it('ALLOWS creating the first-owner invite for a business with zero staff docs', async () => {
    await seedSuperAdmin(ADMIN_UID);
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertSucceeds(
      setDoc(doc(db, 'businesses/fresh-biz/invites/newowner@example.com'), {
        name: 'New Owner',
        role: 'owner',
        invitedAt: new Date(),
        invitedBy: ADMIN_UID,
      }),
    );
  });

  it('DENIES the exact same invite-creation action for a signed-in user who is neither an owner nor a super-admin', async () => {
    const db = asUser('stranger-uid', 'stranger@example.com');
    await assertFails(
      setDoc(doc(db, 'businesses/fresh-biz/invites/newowner@example.com'), {
        name: 'New Owner',
        role: 'owner',
        invitedAt: new Date(),
        invitedBy: 'stranger-uid',
      }),
    );
  });
});

describe('super-admin — read access across a business it has no staff doc in at all', () => {
  it('ALLOWS reading the business document itself', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}`), { name: 'Other Owner\'s Biz' });
    });
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertSucceeds(getDoc(doc(db, `businesses/${BIZ}`)));
  });

  it('ALLOWS reading any staff doc on the business, not just its own (which does not exist)', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertSucceeds(getDoc(doc(db, `businesses/${BIZ}/staff/real-owner-uid`)));
  });

  it('ALLOWS reading sales', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/sales/sale-1`), { total: 5000, method: 'cash' });
    });
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertSucceeds(getDocs(collection(db, `businesses/${BIZ}/sales`)));
  });

  it('ALLOWS reading customers', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/customers/cust-1`), { name: 'A Customer', balance: 0 });
    });
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertSucceeds(getDocs(collection(db, `businesses/${BIZ}/customers`)));
  });

  it('ALLOWS reading shiftHistory', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/shiftHistory/shift-1`), { cashTotalNaira: 1000 });
    });
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertSucceeds(getDocs(collection(db, `businesses/${BIZ}/shiftHistory`)));
  });

  it('DENIES that same read to a signed-in stranger with no staff doc and no super-admin membership', async () => {
    await seedOwner(BIZ, 'real-owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/sales/sale-1`), { total: 5000, method: 'cash' });
    });
    const db = asUser('stranger-uid', 'stranger@example.com');
    await assertFails(getDocs(collection(db, `businesses/${BIZ}/sales`)));
  });
});

describe('super-admin — the actual boundary: cannot write a single thing to another business\'s operational data', () => {
  it('DENIES creating a sale', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/shiftState/current`), { openingFloatNaira: 0, cashTotalNaira: 0 });
    });
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/sales/rogue-sale`), { total: 999999, method: 'cash' }),
    );
  });

  it('DENIES adjusting a customer balance', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/customers/cust-1`), { name: 'A Customer', balance: 0 });
    });
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/customers/cust-1`), { balance: -999999 }, { merge: true }),
    );
  });

  it('DENIES writing gas stock units', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 100000, rate: 1500 });
    });
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/gasStock/current`), { units: 999999999 }, { merge: true }),
    );
  });

  it('DENIES updating a product', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/products/prod-1`), {
        name: 'Regulator',
        price: 5000,
        stockCount: 10,
        categoryId: 'cat-1',
        unit: 'piece',
      });
    });
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/products/prod-1`), { stockCount: 0 }, { merge: true }),
    );
  });

  it('DENIES opening a shift (shiftState create)', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/shiftState/current`), { openingFloatNaira: 0, cashTotalNaira: 0 }),
    );
  });

  it('DENIES closing a shift (shiftState delete)', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/shiftState/current`), {
        openingFloatNaira: 0,
        cashTotalNaira: 0,
        plannedHistoryId: 'history-1',
      });
    });
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/shiftState/current`)));
  });

  it('DENIES updating an EXISTING business\'s own document (name/settings) — that stays owner-only, unchanged', async () => {
    await seedSuperAdmin(ADMIN_UID);
    await seedOwner(BIZ, 'real-owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}`), { name: 'Other Owner\'s Biz', settings: { gasTankCapacityKg: 100 } });
    });
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}`), { settings: { gasTankCapacityKg: 9999 } }, { merge: true }),
    );
  });
});

describe('platformConfig/superAdmins — unreadable and unwritable by any client, even a recognized super-admin', () => {
  it('DENIES a seeded super-admin from reading the super-admin list document itself', async () => {
    await seedSuperAdmin(ADMIN_UID);
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertFails(getDoc(doc(db, 'platformConfig/superAdmins')));
  });

  it('DENIES a seeded super-admin from adding another uid to the list — membership changes are console/Admin-SDK-only', async () => {
    await seedSuperAdmin(ADMIN_UID);
    const db = asUser(ADMIN_UID, ADMIN_EMAIL);
    await assertFails(
      setDoc(doc(db, 'platformConfig/superAdmins'), { uids: [ADMIN_UID, 'sneaky-new-admin'] }),
    );
  });

  it('DENIES an ordinary signed-in stranger from reading or writing it', async () => {
    const db = asUser('stranger-uid', 'stranger@example.com');
    await assertFails(getDoc(doc(db, 'platformConfig/superAdmins')));
    await assertFails(setDoc(doc(db, 'platformConfig/superAdmins'), { uids: ['stranger-uid'] }));
  });
});
