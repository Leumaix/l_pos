// Security-rules tests for the in-app staff invite feature, run against
// the Firestore emulator (free, no Blaze needed) — never the live
// project. Run with: npm test (from this directory), with
// `firebase emulators:start --only firestore` already running.
//
// Covers exactly the failure modes that matter, per the design:
//   1. create a staff doc with NO invite at all -> denied
//   2. create a staff doc whose written role does NOT match the
//      invite's role (e.g. invite says attendant, write says owner) -> denied
//   3. create a staff doc under a DIFFERENT business than the one the
//      invite actually belongs to -> denied
//   4. reuse an invite that's already been consumed (deleted) -> denied
// Plus the invite collection's own create/delete/read rules (owner-only
// write, self-or-owner read), and positive controls proving the allowed
// paths actually work — a rules suite that only tests denials can't
// tell a real gate from a rule that denies everything.

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
import { doc, setDoc, getDoc, deleteDoc, getDocs, collection, writeBatch } from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BIZ = 'test-biz';
const OTHER_BIZ = 'other-biz';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-leumadepos-rules-test',
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

async function seedOwner(businessId, uid) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/staff/${uid}`), {
      name: 'Existing Owner',
      role: 'owner',
      active: true,
    });
  });
}

async function seedInvite(businessId, email, { name = 'Invitee', role = 'attendant', invitedBy = 'owner-uid' } = {}) {
  await seed(async (db) => {
    await setDoc(doc(db, `businesses/${businessId}/invites/${email}`), {
      name,
      role,
      invitedAt: new Date(),
      invitedBy,
    });
  });
}

function asUser(uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: true }).firestore();
}

// platformConfig/superAdmins is unreadable/unwritable from any client
// (see firestore.rules) — seeding it always goes through the same
// rules-bypass context every other fixture in this suite uses.
async function seedSuperAdmin(uid) {
  await seed(async (db) => {
    await setDoc(doc(db, 'platformConfig/superAdmins'), { uids: [uid] });
  });
}

function asUnverifiedUser(uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: false }).firestore();
}

describe('staff self-provisioning (allow create on /staff/{uid})', () => {
  it('DENIES creating a staff doc with no invite at all', async () => {
    const db = asUser('stranger-uid', 'stranger@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/staff/stranger-uid`), {
        name: 'Stranger',
        role: 'attendant',
        active: true,
      }),
    );
  });

  it('ALLOWS creating a staff doc when a real invite exists and the role matches exactly (positive control)', async () => {
    await seedInvite(BIZ, 'newhire@example.com', { name: 'New Hire', role: 'attendant', invitedBy: 'owner-uid' });
    const db = asUser('newhire-uid', 'newhire@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/staff/newhire-uid`), {
        name: 'New Hire',
        role: 'attendant',
        active: true,
      }),
    );
  });

  it('DENIES creating a staff doc whose written role does not match the invite\'s role (self-granted "owner")', async () => {
    await seedInvite(BIZ, 'sneaky@example.com', { name: 'Sneaky', role: 'attendant', invitedBy: 'owner-uid' });
    const db = asUser('sneaky-uid', 'sneaky@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/staff/sneaky-uid`), {
        name: 'Sneaky',
        role: 'owner', // invite said attendant — this must be rejected
        active: true,
      }),
    );
  });

  it('DENIES creating a staff doc under a DIFFERENT business than the one the invite belongs to', async () => {
    // Invite exists, but only under BIZ — not OTHER_BIZ.
    await seedInvite(BIZ, 'crossbiz@example.com', { name: 'Cross Biz', role: 'attendant', invitedBy: 'owner-uid' });
    const db = asUser('crossbiz-uid', 'crossbiz@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${OTHER_BIZ}/staff/crossbiz-uid`), {
        name: 'Cross Biz',
        role: 'attendant',
        active: true,
      }),
    );
  });

  it('DENIES reusing an invite that has already been consumed (deleted)', async () => {
    await seedInvite(BIZ, 'used@example.com', { name: 'Used', role: 'attendant', invitedBy: 'owner-uid' });
    // Simulate the app's own atomic consume-and-delete already having
    // happened for this invite (by some earlier, legitimate attempt).
    await seed(async (db) => {
      await deleteDoc(doc(db, `businesses/${BIZ}/invites/used@example.com`));
    });

    const db = asUser('used-again-uid', 'used@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/staff/used-again-uid`), {
        name: 'Used',
        role: 'attendant',
        active: true,
      }),
    );
  });

  it('DENIES creating a staff doc for someone ELSE\'s uid, even with a valid invite for the caller', async () => {
    await seedInvite(BIZ, 'me@example.com', { name: 'Me', role: 'attendant', invitedBy: 'owner-uid' });
    const db = asUser('me-uid', 'me@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/staff/someone-else-uid`), {
        name: 'Me',
        role: 'attendant',
        active: true,
      }),
    );
  });

  it('DENIES creating a staff doc when email_verified is false, even with a matching invite', async () => {
    await seedInvite(BIZ, 'unverified@example.com', { name: 'Unverified', role: 'attendant', invitedBy: 'owner-uid' });
    const db = asUnverifiedUser('unverified-uid', 'unverified@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/staff/unverified-uid`), {
        name: 'Unverified',
        role: 'attendant',
        active: true,
      }),
    );
  });

  it('DENIES an unauthenticated request outright', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/staff/nobody-uid`), {
        name: 'Nobody',
        role: 'attendant',
        active: true,
      }),
    );
  });

  it('DENIES updating an existing staff doc via the create path (already-provisioned uid)', async () => {
    await seedOwner(BIZ, 'existing-owner-uid');
    // Even with a (contrived) invite present, an existing doc can never
    // be touched by this path — allow create only ever applies to a
    // brand-new document; update/delete stay hard-denied.
    await seedInvite(BIZ, 'owner@example.com', { name: 'Existing Owner', role: 'owner', invitedBy: 'owner-uid' });
    const db = asUser('existing-owner-uid', 'owner@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/staff/existing-owner-uid`), {
        name: 'Existing Owner',
        role: 'owner',
        active: true,
      }),
    );
  });
});

// A real rules bug shipped and went undetected for a while because every
// test above exercises `allow create` on /staff in ISOLATION via a lone
// setDoc — never bundled with the invite delete the real client always
// commits alongside it (FirebaseAuthRepository._loadStaffDoc: one atomic
// batch, staff-doc create + invite delete, so a half-finished attempt
// can never be observed). A batch fails as a WHOLE if any single
// operation inside it is denied, even if that operation would succeed
// entirely on its own — so this needs its own coverage using the exact
// same writeBatch a real self-provisioning attempt performs, not a
// second isolated setDoc/deleteDoc pair.
describe('self-provisioning as the real client actually does it (one atomic batch: staff.create + invite.delete)', () => {
  it('ALLOWS the full batch for a brand-new attendant consuming their own invite', async () => {
    await seedInvite(BIZ, 'newhire@example.com', { name: 'New Hire', role: 'attendant', invitedBy: 'owner-uid' });
    const db = asUser('newhire-uid', 'newhire@example.com');

    const batch = writeBatch(db);
    batch.set(doc(db, `businesses/${BIZ}/staff/newhire-uid`), {
      name: 'New Hire',
      role: 'attendant',
      active: true,
    });
    batch.delete(doc(db, `businesses/${BIZ}/invites/newhire@example.com`));
    await assertSucceeds(batch.commit());
  });

  it('ALLOWS the full batch for a brand-new OWNER consuming their own owner-role invite too — '
    + 'not just attendants', async () => {
    await seedInvite(BIZ, 'newowner@example.com', { name: 'New Owner', role: 'owner', invitedBy: 'owner-uid' });
    const db = asUser('newowner-uid', 'newowner@example.com');

    const batch = writeBatch(db);
    batch.set(doc(db, `businesses/${BIZ}/staff/newowner-uid`), {
      name: 'New Owner',
      role: 'owner',
      active: true,
    });
    batch.delete(doc(db, `businesses/${BIZ}/invites/newowner@example.com`));
    await assertSucceeds(batch.commit());
  });

  it('DENIES the batch outright if the role written does not match the invite — '
    + 'the create half alone denies it, so the whole batch fails', async () => {
    await seedInvite(BIZ, 'sneaky@example.com', { name: 'Sneaky', role: 'attendant', invitedBy: 'owner-uid' });
    const db = asUser('sneaky-uid', 'sneaky@example.com');

    const batch = writeBatch(db);
    batch.set(doc(db, `businesses/${BIZ}/staff/sneaky-uid`), {
      name: 'Sneaky',
      role: 'owner', // invite said attendant
      active: true,
    });
    batch.delete(doc(db, `businesses/${BIZ}/invites/sneaky@example.com`));
    await assertFails(batch.commit());
  });
});

describe('invite management (/invites/{email})', () => {
  it('ALLOWS an active owner to create an invite', async () => {
    await seedOwner(BIZ, 'owner-uid');
    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/invites/hire@example.com`), {
        name: 'Hire',
        role: 'attendant',
        invitedAt: new Date(),
        invitedBy: 'owner-uid',
      }),
    );
  });

  it('DENIES a non-owner (active attendant) from creating an invite', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/staff/attendant-uid`), {
        name: 'Attendant',
        role: 'attendant',
        active: true,
      });
    });
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/invites/hire@example.com`), {
        name: 'Hire',
        role: 'attendant',
        invitedAt: new Date(),
        invitedBy: 'attendant-uid',
      }),
    );
  });

  it('DENIES an unauthenticated request from creating an invite', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/invites/hire@example.com`), {
        name: 'Hire',
        role: 'attendant',
        invitedAt: new Date(),
        invitedBy: 'nobody',
      }),
    );
  });

  it('ALLOWS a seeded platform super-admin to create the first-owner invite for a business with zero staff — '
    + 'the circular case isActiveOwnerOf alone can never satisfy', async () => {
    // Deliberately no seedOwner/seedAttendant anywhere under BRAND_NEW —
    // no staff doc exists for anyone, exactly the moment this carve-out
    // is for.
    const BRAND_NEW = 'brand-new-biz';
    await seedSuperAdmin('super-admin-uid');
    const db = asUser('super-admin-uid', 'admin@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BRAND_NEW}/invites/firstowner@example.com`), {
        name: 'First Owner',
        role: 'owner',
        invitedAt: new Date(),
        invitedBy: 'super-admin-uid',
      }),
    );
  });

  it('ALLOWS an active owner to delete (revoke) a pending invite', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedInvite(BIZ, 'revoke-me@example.com');
    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(deleteDoc(doc(db, `businesses/${BIZ}/invites/revoke-me@example.com`)));
  });

  it('DENIES a non-owner from deleting a pending invite', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/staff/attendant-uid`), {
        name: 'Attendant',
        role: 'attendant',
        active: true,
      });
    });
    await seedInvite(BIZ, 'revoke-me@example.com');
    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/invites/revoke-me@example.com`)));
  });

  it('ALLOWS a signed-in user with NO staff doc at all yet to delete ONLY their own matching invite — '
    + 'the self-provisioning consumption case this rule exists for, in isolation', async () => {
    await seedInvite(BIZ, 'newhire@example.com', { name: 'New Hire', role: 'attendant', invitedBy: 'owner-uid' });
    // Deliberately no seedOwner/seedAttendant here — this uid has no
    // staff doc of any kind, exactly the moment mid-provisioning where
    // the real client's batch commits this delete.
    const db = asUser('newhire-uid', 'newhire@example.com');
    await assertSucceeds(deleteDoc(doc(db, `businesses/${BIZ}/invites/newhire@example.com`)));
  });

  it('DENIES that same not-yet-provisioned user from deleting someone ELSE\'s invite', async () => {
    await seedInvite(BIZ, 'someone-else@example.com', { name: 'Someone Else', role: 'attendant', invitedBy: 'owner-uid' });
    const db = asUser('newhire-uid', 'newhire@example.com');
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/invites/someone-else@example.com`)));
  });

  it('ALLOWS a signed-in user to read ONLY the invite matching their own auth email', async () => {
    await seedInvite(BIZ, 'self@example.com');
    const db = asUser('self-uid', 'self@example.com');
    await assertSucceeds(getDoc(doc(db, `businesses/${BIZ}/invites/self@example.com`)));
  });

  it('DENIES a signed-in user from reading someone ELSE\'s invite', async () => {
    await seedInvite(BIZ, 'someone-else@example.com');
    const db = asUser('nosy-uid', 'nosy@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/invites/someone-else@example.com`)));
  });

  it('ALLOWS an active owner to read the full pending-invites list', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedInvite(BIZ, 'one@example.com');
    await seedInvite(BIZ, 'two@example.com');
    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(getDocs(collection(db, `businesses/${BIZ}/invites`)));
  });

  it('DENIES an update to an existing invite (re-invite is delete-then-create, never an edit)', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seedInvite(BIZ, 'edit-me@example.com', { role: 'attendant' });
    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/invites/edit-me@example.com`), {
        name: 'Edited',
        role: 'owner',
        invitedAt: new Date(),
        invitedBy: 'owner-uid',
      }),
    );
  });
});
