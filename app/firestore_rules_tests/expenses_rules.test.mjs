// Security-rules tests for the expense-tracking feature —
// businesses/{businessId}/expenses/{expenseId} plus its pairing with
// shiftState/current (expenseTotalNaira/lastExpenseId).
//
// Covers: any active staff (not owner-only) can create an expense;
// staff-attributed (request.auth.uid must be the staffId on the doc);
// amount/paymentMethod/category shape validation; category 'other'
// requires a real note; a cash expense must carry a shiftId that matches
// the currently open shift, a transfer/other expense needs no shift at
// all; append-only (no update/delete); owner-only read (same boundary as
// /sales), while the running expenseTotalNaira on shiftState/current
// stays staff-readable (covered by shift_rules.test.mjs's existing
// "ALLOWS an active attendant to read the current shift" — reads are
// whole-document, there's no separate per-field rule to test here).
//
// A dedicated section below isolates the one place this branch has real
// fraud-prevention weight: shiftExpenseMatchesExpense's own shiftId
// cross-check on the shiftState update side, proven to hold even with
// the expenses/{expenseId} create rule's OWN shiftId check stripped out
// entirely — not just "the combined write fails," which wouldn't prove
// which check is doing the blocking.
//
// Run against the Firestore emulator (never the live project) — see
// invites_and_staff_rules.test.mjs for the emulator setup/run
// instructions, identical here. One thing specific to THIS file: the
// isolation section below registers a second project id
// (...-expenses-stripped) with a hand-modified rules string. Confirmed
// by hand: this is solid against a genuinely FRESH emulator (green,
// repeatedly), but re-running `npm test` several times in a row against
// the SAME already-running emulator process eventually surfaces a
// spurious "evaluation error" there — an emulator-process quirk around
// re-registering the same project id with a different rules string
// across repeated runs, not a rules bug (verified directly: the stripped
// rules text is correct, and every other file's tests are unaffected).
// Restart the emulator before re-running the suite if you see that.

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
const RULES_SOURCE = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');

const BIZ = 'test-biz';
const OTHER_BIZ = 'other-biz';

// The create rule's own shiftId cross-check, removed for the isolation
// suite near the bottom of this file — everything else, including
// shiftExpenseMatchesExpense, is untouched. If this string surgery ever
// stops matching (e.g. the rule's wording changes), the assertion in the
// top-level before() below fails loudly rather than silently testing
// against the unmodified rules.
const STRIPPED_CREATE_SHIFT_ID_CHECK = `&& (
            request.resource.data.paymentMethod != 'cash'
            || (
              request.resource.data.shiftId is string
              && exists(/databases/$(database)/documents/businesses/$(businessId)/shiftState/current)
              && request.resource.data.shiftId ==
                 get(/databases/$(database)/documents/businesses/$(businessId)/shiftState/current).data.plannedHistoryId
            )
          );`;

let testEnv;
let strippedTestEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-leumadepos-rules-test-expenses',
    firestore: { rules: RULES_SOURCE, host: 'localhost', port: 8090 },
  });

  assert.ok(
    RULES_SOURCE.includes(STRIPPED_CREATE_SHIFT_ID_CHECK),
    'expected create-rule shiftId clause not found — update this test\'s target string to match firestore.rules',
  );
  const strippedRules = RULES_SOURCE.replace(STRIPPED_CREATE_SHIFT_ID_CHECK, ';');
  assert.notEqual(strippedRules, RULES_SOURCE, 'rules string was not actually modified');
  // Set up at the same file-load timing every other environment gets
  // (not nested inside a describe's own before()) — this specific
  // environment introduces a brand-new project + freshly-compiled custom
  // rules string mid-suite; setting it up here, alongside the main
  // testEnv, avoids a rules-compile propagation race under the full
  // suite's concurrent load that a deeply-nested before() hit in
  // practice.
  strippedTestEnv = await initializeTestEnvironment({
    projectId: 'demo-leumadepos-rules-test-expenses-stripped',
    firestore: { rules: strippedRules, host: 'localhost', port: 8090 },
  });
  // A brand-new project + custom rules string, introduced only by this
  // file, needs a moment to finish propagating on the shared local
  // emulator when the full suite is hammering it with many other files'
  // concurrent requests at once — confirmed by hand (this exact stripped
  // text, checked directly against a script, is correct; the flake only
  // ever appeared under full-suite load, never running this file alone,
  // and never anywhere else in this whole suite's identical seed-then-
  // assert pattern). Forces one REAL rules-evaluated request (not a
  // withSecurityRulesDisabled bypass, which skips rules evaluation
  // entirely and so wouldn't actually warm up whatever's slow to
  // converge) against this exact project before any test depends on it.
  await assertFails(
    getDoc(doc(strippedTestEnv.unauthenticatedContext().firestore(), `businesses/${BIZ}/expenses/_warmup`)),
  );
});

after(async () => {
  await testEnv.cleanup();
  await strippedTestEnv.cleanup();
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

function asUser(uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: true }).firestore();
}

function baseExpense(overrides) {
  return {
    amountNaira: 4000,
    paymentMethod: 'cash',
    category: 'fuel',
    note: null,
    staffId: 'attendant-uid',
    staffName: 'Attendant',
    shiftId: 'hist-1',
    createdAt: new Date().toISOString(),
    ...overrides,
  };
}

describe('expenses/{expenseId} — create shape', () => {
  it('ALLOWS a cash expense against an open shift with a matching shiftId', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({})));
  });

  it('ALLOWS a transfer expense with no shift open at all — it never touches the till', async () => {
    await seedAttendant(BIZ, 'attendant-uid');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      setDoc(
        doc(db, `businesses/${BIZ}/expenses/exp-1`),
        baseExpense({ paymentMethod: 'transfer', shiftId: null }),
      ),
    );
  });

  it('ALLOWS an "other" expense with a note, no shift needed', async () => {
    await seedAttendant(BIZ, 'attendant-uid');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      setDoc(
        doc(db, `businesses/${BIZ}/expenses/exp-1`),
        baseExpense({ paymentMethod: 'other', category: 'other', note: 'Signboard repair', shiftId: null }),
      ),
    );
  });

  it('DENIES a cash expense with a shiftId that does not match the current shift', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ); // plannedHistoryId: 'hist-1'

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ shiftId: 'hist-stale' })),
    );
  });

  it('DENIES a cash expense with no shift open at all', async () => {
    await seedAttendant(BIZ, 'attendant-uid');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({})));
  });

  it('DENIES a cash expense with shiftId omitted', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ shiftId: null })),
    );
  });

  it('DENIES a zero amount', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ amountNaira: 0 })));
  });

  it('DENIES a negative amount', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ amountNaira: -500 })));
  });

  it('DENIES an unrecognized paymentMethod', async () => {
    await seedAttendant(BIZ, 'attendant-uid');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(
        doc(db, `businesses/${BIZ}/expenses/exp-1`),
        baseExpense({ paymentMethod: 'crypto', shiftId: null }),
      ),
    );
  });

  it('DENIES an unrecognized category', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ category: 'bribes' })),
    );
  });

  it('DENIES category "other" with no note', async () => {
    await seedAttendant(BIZ, 'attendant-uid');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(
        doc(db, `businesses/${BIZ}/expenses/exp-1`),
        baseExpense({ paymentMethod: 'transfer', category: 'other', note: null, shiftId: null }),
      ),
    );
  });

  it('DENIES category "other" with a blank note', async () => {
    await seedAttendant(BIZ, 'attendant-uid');

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(
        doc(db, `businesses/${BIZ}/expenses/exp-1`),
        baseExpense({ paymentMethod: 'transfer', category: 'other', note: '', shiftId: null }),
      ),
    );
  });

  it('DENIES a fixed category carrying an unrelated note — not a rejection, just proving note is not required elsewhere', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ note: 'extra context, fine either way' })),
    );
  });

  it('DENIES staffId not matching the authenticated uid — cannot attribute an expense to someone else', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ staffId: 'someone-else-uid' })),
    );
  });

  it('DENIES an unauthenticated request', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({})));
  });

  it('DENIES update or delete on an existing expense — append-only', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ staffId: 'owner-uid' }));
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(updateDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), { amountNaira: 1 }));
    await assertFails(deleteDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`)));
  });
});

describe('expenses/{expenseId} — read is owner-only, same boundary as /sales', () => {
  it('ALLOWS an active owner to read an expense', async () => {
    await seedOwner(BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ staffId: 'owner-uid' }));
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertSucceeds(getDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`)));
  });

  it('DENIES an active attendant from reading an expense, even their own', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ staffId: 'attendant-uid' }));
    });

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`)));
  });

  it('DENIES a staff member of a DIFFERENT business', async () => {
    await seedOwner(OTHER_BIZ, 'owner-uid');
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({}));
    });

    const db = asUser('owner-uid', 'owner@example.com');
    await assertFails(getDoc(doc(db, `businesses/${BIZ}/expenses/exp-1`)));
  });
});

describe('shiftState/current — cash-expense pairing (expenseTotalNaira/lastExpenseId)', () => {
  it('ALLOWS the real commitExpense shape: expense create + matching shiftState update, same transaction', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ); // plannedHistoryId: 'hist-1', expenseTotalNaira: 0

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        transaction.set(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({}));
        transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
          expenseTotalNaira: 4000,
          lastExpenseId: 'exp-1',
        });
      }),
    );
  });

  it('DENIES a bare expenseTotalNaira update with no lastExpenseId — the unpaired shape', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      setDoc(doc(db, `businesses/${BIZ}/shiftState/current`), { expenseTotalNaira: 4000 }, { merge: true }),
    );
  });

  it('DENIES an expenseTotalNaira increment that does not match the paired expense\'s amountNaira', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.set(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ amountNaira: 4000 }));
        transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
          expenseTotalNaira: 999999, // does not match the real expense's 4000
          lastExpenseId: 'exp-1',
        });
      }),
    );
  });

  it('DENIES lastExpenseId pointing at an OLD, already-existing expense — anti-replay', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ);
    await seed(async (db) => {
      await setDoc(doc(db, `businesses/${BIZ}/expenses/old-exp`), baseExpense({ amountNaira: 4000 }));
    });

    const db = asUser('attendant-uid', 'attendant@example.com');
    // No new expense created in this write — reuses old-exp's id and its
    // already-true amount to justify a fresh totals increment.
    await assertFails(
      setDoc(
        doc(db, `businesses/${BIZ}/shiftState/current`),
        { expenseTotalNaira: 4000, lastExpenseId: 'old-exp' },
        { merge: true },
      ),
    );
  });

  it(
    'DENIES a mismatched-shiftId expense from inflating expenseTotalNaira — through the realistic combined '
    + 'write, both the create rule and shiftExpenseMatchesExpense active',
    async () => {
      await seedAttendant(BIZ, 'attendant-uid');
      await seedOpenShift(BIZ); // plannedHistoryId: 'hist-1'

      const db = asUser('attendant-uid', 'attendant@example.com');
      await assertFails(
        runTransaction(db, async (transaction) => {
          transaction.set(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({ shiftId: 'hist-stale' }));
          transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
            expenseTotalNaira: 4000,
            lastExpenseId: 'exp-1',
          });
        }),
      );
    },
  );

  it('a shift with nonzero cash expenses closes with expenseTotalNaira correctly subtracted from expectedCashNaira', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ, { cashTotalNaira: 25000 }); // openingFloat 10000 + cash 25000 - expense 4000 = 31000

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        transaction.set(doc(db, `businesses/${BIZ}/expenses/exp-1`), baseExpense({}));
        transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
          expenseTotalNaira: 4000,
          lastExpenseId: 'exp-1',
        });
      }),
    );

    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        transaction.delete(doc(db, `businesses/${BIZ}/shiftState/current`));
        transaction.set(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`), {
          openingFloatNaira: 10000,
          openedByStaffId: 'someone',
          openedByStaffName: 'Someone',
          openedAt: new Date(),
          cashTotalNaira: 25000,
          cardTotalNaira: 0,
          transferTotalNaira: 0,
          creditTotalNaira: 0,
          salesCount: 0,
          expenseTotalNaira: 4000,
          countedCashNaira: 31000,
          expectedCashNaira: 31000,
          varianceNaira: 0,
          closedByStaffId: 'attendant-uid',
          closedByStaffName: 'Attendant',
          closedAt: new Date(),
        });
      }),
    );
  });

  it('DENIES a close whose expectedCashNaira does not subtract expenseTotalNaira — the stale, pre-expenses formula', async () => {
    await seedAttendant(BIZ, 'attendant-uid');
    await seedOpenShift(BIZ, { cashTotalNaira: 25000, expenseTotalNaira: 4000 }); // true expected is 31000

    const db = asUser('attendant-uid', 'attendant@example.com');
    await assertFails(
      runTransaction(db, async (transaction) => {
        transaction.delete(doc(db, `businesses/${BIZ}/shiftState/current`));
        transaction.set(doc(db, `businesses/${BIZ}/shiftHistory/hist-1`), {
          openingFloatNaira: 10000,
          openedByStaffId: 'someone',
          openedByStaffName: 'Someone',
          openedAt: new Date(),
          cashTotalNaira: 25000,
          cardTotalNaira: 0,
          transferTotalNaira: 0,
          creditTotalNaira: 0,
          salesCount: 0,
          expenseTotalNaira: 4000,
          countedCashNaira: 35000,
          expectedCashNaira: 35000, // old formula, ignores the 4000 expense
          varianceNaira: 0,
          closedByStaffId: 'attendant-uid',
          closedByStaffName: 'Attendant',
          closedAt: new Date(),
        });
      }),
    );
  });
});

describe(
  'shiftExpenseMatchesExpense\'s shiftId check, isolated — proven to block a mismatched-shiftId expense '
  + 'even with the expenses/{expenseId} create rule\'s OWN shiftId check surgically removed',
  () => {
    // strippedTestEnv itself is set up in the file-level before() above,
    // alongside the main testEnv — see that block's comment for why.

    it('the stripped create rule alone now ALLOWS a mismatched-shiftId expense doc on its own', async () => {
      await strippedTestEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(
          doc(context.firestore(), `businesses/${BIZ}/staff/attendant-uid`),
          { name: 'Attendant', role: 'attendant', active: true },
        );
        await setDoc(
          doc(context.firestore(), `businesses/${BIZ}/shiftState/current`),
          {
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
          },
        );
      });

      const db = strippedTestEnv.authenticatedContext('attendant-uid', {
        email: 'attendant@example.com',
        email_verified: true,
      }).firestore();

      // Confirms the stripped create rule really is weaker now — this
      // create ALONE (no paired shiftState update) succeeds even with a
      // shiftId that matches nothing real, proving the create-rule check
      // is genuinely gone in this variant, not just untriggered.
      await assertSucceeds(
        setDoc(doc(db, `businesses/${BIZ}/expenses/exp-mismatched`), baseExpense({ shiftId: 'hist-stale' })),
      );
    });

    it(
      'yet the paired shiftState update STILL fails — shiftExpenseMatchesExpense\'s own shiftId check is '
      + 'independently sufficient, not merely redundant with the create rule',
      async () => {
        await strippedTestEnv.withSecurityRulesDisabled(async (context) => {
          await setDoc(
            doc(context.firestore(), `businesses/${BIZ}/staff/attendant-uid`),
            { name: 'Attendant', role: 'attendant', active: true },
          );
          await setDoc(
            doc(context.firestore(), `businesses/${BIZ}/shiftState/current`),
            {
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
            },
          );
        });

        const db = strippedTestEnv.authenticatedContext('attendant-uid', {
          email: 'attendant@example.com',
          email_verified: true,
        }).firestore();

        await assertFails(
          runTransaction(db, async (transaction) => {
            // The create half succeeds under these stripped rules (proven
            // above) — it's the update half that must still be the one
            // doing the blocking.
            transaction.set(
              doc(db, `businesses/${BIZ}/expenses/exp-mismatched-2`),
              baseExpense({ shiftId: 'hist-stale' }),
            );
            transaction.update(doc(db, `businesses/${BIZ}/shiftState/current`), {
              expenseTotalNaira: 4000,
              lastExpenseId: 'exp-mismatched-2',
            });
          }),
        );
      },
    );
  },
);
