import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:leumadepos/features/auth/data/auth_repository.dart';
import 'package:leumadepos/features/auth/data/web_auth_repository.dart';

class _MockFirebaseAuth extends Mock implements fb_auth.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb_auth.UserCredential {}

class _MockUser extends Mock implements fb_auth.User {}

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _MockWriteBatch extends Mock implements WriteBatch {}

void main() {
  setUpAll(() {
    registerFallbackValue(_MockDocumentReference());
    registerFallbackValue(fb_auth.Persistence.NONE);
  });

  late _MockFirebaseAuth auth;
  late _MockFirebaseFirestore firestore;
  late _MockDocumentReference staffRef;
  late _MockDocumentReference inviteRef;
  late _MockDocumentSnapshot staffSnapshot;
  late _MockDocumentSnapshot inviteSnapshot;
  late _MockWriteBatch batch;
  late WebAuthRepository repository;

  const uid = 'uid-1';
  const email = 'owner@example.com';
  const password = 'correct-horse-battery-staple';

  setUp(() {
    auth = _MockFirebaseAuth();
    firestore = _MockFirebaseFirestore();
    staffRef = _MockDocumentReference();
    inviteRef = _MockDocumentReference();
    staffSnapshot = _MockDocumentSnapshot();
    inviteSnapshot = _MockDocumentSnapshot();
    batch = _MockWriteBatch();

    when(() => firestore.doc('businesses/ph-zazaa/staff/$uid'))
        .thenReturn(staffRef);
    when(() => firestore.doc('businesses/ph-zazaa/invites/$email'))
        .thenReturn(inviteRef);
    when(() => staffRef.get()).thenAnswer((_) async => staffSnapshot);
    when(() => inviteRef.get()).thenAnswer((_) async => inviteSnapshot);
    when(() => firestore.batch()).thenReturn(batch);
    when(() => batch.set(any(), any())).thenReturn(null);
    when(() => batch.delete(any())).thenReturn(null);
    when(() => batch.commit()).thenAnswer((_) async {});

    repository = WebAuthRepository(auth: auth, firestore: firestore);
  });

  test('never calls setPersistence — that call is not idempotent and wipes an already-persisted session on the SDK we use, so browserLocalPersistence is left as the untouched default', () {
    verifyNever(() => auth.setPersistence(any()));
  });

  group('signUp', () {
    test('creates the account and sends exactly one verification email — no self-provisioning yet', () async {
      final fbUser = _MockUser();
      final credential = _MockUserCredential();
      when(() => credential.user).thenReturn(fbUser);
      when(() => fbUser.sendEmailVerification()).thenAnswer((_) async {});
      when(
        () => auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        ),
      ).thenAnswer((_) async => credential);

      await repository.signUp(
        email: '  Owner@Example.com  ',
        password: password,
      );

      verify(
        () => auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        ),
      ).called(1);
      verify(() => fbUser.sendEmailVerification()).called(1);
      // Not signed in yet as far as the app is concerned — self-provisioning hasn't run.
      expect(repository.currentUser, isNull);
      expect(repository.activeFirestore, isNull);
    });
  });

  group('sendPasswordResetEmail', () {
    test('normalizes the email and forwards to Firebase — the one recovery path for an account '
        'stuck with no password credential (old email-link account, or any other cause)', () async {
      when(() => auth.sendPasswordResetEmail(email: email))
          .thenAnswer((_) async {});

      await repository.sendPasswordResetEmail('  Owner@Example.com  ');

      verify(() => auth.sendPasswordResetEmail(email: email)).called(1);
    });

    test('lets FirebaseAuthException propagate as-is', () async {
      when(() => auth.sendPasswordResetEmail(email: email))
          .thenThrow(fb_auth.FirebaseAuthException(code: 'user-not-found'));

      await expectLater(
        () => repository.sendPasswordResetEmail(email),
        throwsA(isA<fb_auth.FirebaseAuthException>()),
      );
    });
  });

  group('resendVerificationEmail', () {
    test('re-sends to whoever Firebase currently has signed in', () async {
      final fbUser = _MockUser();
      when(() => fbUser.sendEmailVerification()).thenAnswer((_) async {});
      when(() => auth.currentUser).thenReturn(fbUser);

      await repository.resendVerificationEmail();

      verify(() => fbUser.sendEmailVerification()).called(1);
    });

    test('throws StateError when nobody is signed in', () async {
      when(() => auth.currentUser).thenReturn(null);
      await expectLater(repository.resendVerificationEmail, throwsStateError);
    });
  });

  group('pendingSignUpUser', () {
    test('is null before any sign-up, and reflects the raw Firebase user once one exists', () {
      when(() => auth.currentUser).thenReturn(null);
      expect(repository.pendingSignUpUser, isNull);

      final fbUser = _MockUser();
      when(() => auth.currentUser).thenReturn(fbUser);
      expect(repository.pendingSignUpUser, same(fbUser));
    });
  });

  group('completeSignUp', () {
    test('throws StateError when nobody is signed in', () async {
      when(() => auth.currentUser).thenReturn(null);
      await expectLater(repository.completeSignUp, throwsStateError);
    });

    test('throws EmailNotVerifiedException when the reloaded user still shows unverified', () async {
      final fbUser = _MockUser();
      when(() => auth.currentUser).thenReturn(fbUser);
      when(() => fbUser.reload()).thenAnswer((_) async {});
      when(() => fbUser.getIdToken(any()))
          .thenAnswer((_) async => 'fake-token');
      when(() => fbUser.emailVerified).thenReturn(false);

      await expectLater(
        repository.completeSignUp,
        throwsA(isA<EmailNotVerifiedException>()),
      );
      expect(repository.currentUser, isNull);
    });

    test('completes into a real AppUser and activates the session once the reload shows verified, '
        'when the staff doc already exists', () async {
      final fbUser = _MockUser();
      when(() => auth.currentUser).thenReturn(fbUser);
      when(() => fbUser.uid).thenReturn(uid);
      when(() => fbUser.email).thenReturn(email);
      // reload() flips emailVerified true, matching how the real SDK
      // updates the same cached User object in place.
      when(() => fbUser.reload()).thenAnswer((_) async {
        when(() => fbUser.emailVerified).thenReturn(true);
      });
      when(() => fbUser.getIdToken(any()))
          .thenAnswer((_) async => 'fake-token');
      when(() => fbUser.emailVerified).thenReturn(false);

      when(() => staffSnapshot.exists).thenReturn(true);
      when(() => staffSnapshot.data()).thenReturn({
        'name': 'Amaka',
        'role': 'owner',
        'active': true,
        'phone': '08000000000',
      });

      final appUser = await repository.completeSignUp();

      expect(appUser.uid, uid);
      expect(appUser.name, 'Amaka');
      expect(appUser.role, 'owner');
      expect(repository.currentUser?.uid, uid);
      expect(repository.activeFirestore, same(firestore));
      expect(
        repository.pendingSignUpUser,
        isNull,
      ); // now a real AppUser, not just pending
    });

    test('self-provisions via a matching owner-issued invite when no staff doc exists yet, '
        'atomically creating the staff doc and consuming the invite', () async {
      final fbUser = _MockUser();
      when(() => auth.currentUser).thenReturn(fbUser);
      when(() => fbUser.uid).thenReturn(uid);
      when(() => fbUser.email).thenReturn(email);
      when(() => fbUser.reload()).thenAnswer((_) async {
        when(() => fbUser.emailVerified).thenReturn(true);
      });
      when(() => fbUser.getIdToken(any()))
          .thenAnswer((_) async => 'fake-token');
      when(() => fbUser.emailVerified).thenReturn(false);

      when(() => staffSnapshot.exists).thenReturn(false);
      when(() => staffSnapshot.data()).thenReturn(null);
      when(() => inviteSnapshot.exists).thenReturn(true);
      when(() => inviteSnapshot.data())
          .thenReturn({'name': 'First Owner', 'role': 'owner'});

      final appUser = await repository.completeSignUp();

      expect(appUser.name, 'First Owner');
      expect(appUser.role, 'owner');
      expect(appUser.phone, isNull);
      verify(
        () => batch.set(staffRef, {
          'name': 'First Owner',
          'role': 'owner',
          'active': true,
        }),
      ).called(1);
      verify(() => batch.delete(inviteRef)).called(1);
      verify(() => batch.commit()).called(1);
    });

    test('throws StaffRecordNotFoundException when verified but there is no staff doc and no matching invite', () async {
      final fbUser = _MockUser();
      when(() => auth.currentUser).thenReturn(fbUser);
      when(() => fbUser.uid).thenReturn(uid);
      when(() => fbUser.email).thenReturn(email);
      when(() => fbUser.reload()).thenAnswer((_) async {
        when(() => fbUser.emailVerified).thenReturn(true);
      });
      when(() => fbUser.getIdToken(any()))
          .thenAnswer((_) async => 'fake-token');
      when(() => fbUser.emailVerified).thenReturn(false);

      when(() => staffSnapshot.exists).thenReturn(false);
      when(() => staffSnapshot.data()).thenReturn(null);
      when(() => inviteSnapshot.exists).thenReturn(false);
      when(() => inviteSnapshot.data()).thenReturn(null);

      await expectLater(
        repository.completeSignUp,
        throwsA(isA<StaffRecordNotFoundException>()),
      );
      expect(repository.currentUser, isNull);
      verifyNever(() => batch.commit());
    });

    test('throws StaffRecordNotFoundException for a deactivated staff member, never falling through to self-provisioning', () async {
      final fbUser = _MockUser();
      when(() => auth.currentUser).thenReturn(fbUser);
      when(() => fbUser.uid).thenReturn(uid);
      when(() => fbUser.email).thenReturn(email);
      when(() => fbUser.reload()).thenAnswer((_) async {
        when(() => fbUser.emailVerified).thenReturn(true);
      });
      when(() => fbUser.getIdToken(any()))
          .thenAnswer((_) async => 'fake-token');
      when(() => fbUser.emailVerified).thenReturn(false);

      when(() => staffSnapshot.exists).thenReturn(true);
      when(() => staffSnapshot.data())
          .thenReturn({'name': 'Amaka', 'role': 'owner', 'active': false});

      await expectLater(
        repository.completeSignUp,
        throwsA(isA<StaffRecordNotFoundException>()),
      );
      verifyNever(() => inviteRef.get());
    });
  });

  group('signIn', () {
    test('normalizes the email and completes into a real AppUser for an existing active staff member', () async {
      final credential = _MockUserCredential();
      final fbUser = _MockUser();
      when(() => fbUser.uid).thenReturn(uid);
      when(() => credential.user).thenReturn(fbUser);
      when(
        () => auth.signInWithEmailAndPassword(email: email, password: password),
      ).thenAnswer((_) async => credential);
      when(() => staffSnapshot.exists).thenReturn(true);
      when(() => staffSnapshot.data())
          .thenReturn({'name': 'Amaka', 'role': 'owner', 'active': true});

      final appUser = await repository.signIn(
        email: '  Owner@Example.com  ',
        password: password,
      );

      expect(appUser.uid, uid);
      expect(repository.currentUser?.uid, uid);
      expect(repository.activeFirestore, same(firestore));
    });

    test('throws StaffRecordNotFoundException when no staff doc and no invite exist for this account', () async {
      final credential = _MockUserCredential();
      final fbUser = _MockUser();
      when(() => fbUser.uid).thenReturn(uid);
      when(() => credential.user).thenReturn(fbUser);
      when(
        () => auth.signInWithEmailAndPassword(email: email, password: password),
      ).thenAnswer((_) async => credential);
      when(() => staffSnapshot.exists).thenReturn(false);
      when(() => staffSnapshot.data()).thenReturn(null);
      when(() => inviteSnapshot.exists).thenReturn(false);
      when(() => inviteSnapshot.data()).thenReturn(null);

      await expectLater(
        () => repository.signIn(email: email, password: password),
        throwsA(isA<StaffRecordNotFoundException>()),
      );
      expect(repository.currentUser, isNull);
    });

    test(
      'lets FirebaseAuthException (e.g. wrong password) propagate as-is',
      () async {
        when(
          () =>
              auth.signInWithEmailAndPassword(email: email, password: password),
        ).thenThrow(fb_auth.FirebaseAuthException(code: 'wrong-password'));

        await expectLater(
          () => repository.signIn(email: email, password: password),
          throwsA(isA<fb_auth.FirebaseAuthException>()),
        );
      },
    );
  });

  group('unsupported members — this repository no longer uses PIN or email-link sign-in', () {
    test('PIN-only methods throw UnsupportedError', () {
      expect(
        () => repository.isDeviceVerifiedFor(email),
        throwsUnsupportedError,
      );
      expect(
        () => repository.signInWithEmailAndPin(email: email, pin: '1234'),
        throwsUnsupportedError,
      );
      expect(
        () => repository.setPinForVerifiedDevice(email: email, pin: '1234'),
        throwsUnsupportedError,
      );
    });

    test('email-link methods throw UnsupportedError', () {
      expect(
        () => repository.sendVerificationLink(email),
        throwsUnsupportedError,
      );
      expect(repository.pendingVerificationEmail, throwsUnsupportedError);
      expect(
        () => repository.completeEmailLinkSignIn(
          email: email,
          emailLink: 'https://example.com/',
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('signOut', () {
    test('really signs out of Firebase (unlike the mobile flow) and clears the session', () async {
      when(() => auth.signOut()).thenAnswer((_) async {});
      final credential = _MockUserCredential();
      final fbUser = _MockUser();
      when(() => fbUser.uid).thenReturn(uid);
      when(() => credential.user).thenReturn(fbUser);
      when(
        () => auth.signInWithEmailAndPassword(email: email, password: password),
      ).thenAnswer((_) async => credential);
      when(() => staffSnapshot.exists).thenReturn(true);
      when(() => staffSnapshot.data())
          .thenReturn({'name': 'Amaka', 'role': 'owner', 'active': true});
      await repository.signIn(email: email, password: password);
      expect(repository.currentUser, isNotNull);

      await repository.signOut();

      verify(() => auth.signOut()).called(1);
      expect(repository.currentUser, isNull);
      expect(repository.activeFirestore, isNull);
    });
  });
}
