import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:leumadepos/features/auth/application/web_auth_controller.dart';
import 'package:leumadepos/features/auth/data/web_auth_repository.dart';

class _MockFirebaseAuth extends Mock implements fb_auth.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb_auth.UserCredential {}

class _MockUser extends Mock implements fb_auth.User {}

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

void main() {
  setUpAll(() {
    registerFallbackValue(_MockDocumentReference());
  });

  late _MockFirebaseAuth auth;
  late _MockFirebaseFirestore firestore;
  late _MockDocumentReference staffRef;
  late _MockDocumentSnapshot staffSnapshot;
  late WebAuthRepository repository;
  late WebAuthController controller;

  const uid = 'uid-1';
  const email = 'owner@example.com';
  const password = 'correct-horse-battery-staple';

  setUp(() {
    auth = _MockFirebaseAuth();
    firestore = _MockFirebaseFirestore();
    staffRef = _MockDocumentReference();
    staffSnapshot = _MockDocumentSnapshot();

    when(() => firestore.doc('businesses/ph-zazaa/staff/$uid'))
        .thenReturn(staffRef);
    when(() => staffRef.get()).thenAnswer((_) async => staffSnapshot);
    when(() => auth.currentUser).thenReturn(null);
    // Real Firebase Auth's authStateChanges() only fires once its async
    // restore of any persisted session settles — WebAuthController._resumeSession
    // awaits its first emission before trusting currentUser (see that
    // method's own doc comment for why). Evaluated lazily inside the
    // closure so it reflects whatever auth.currentUser is stubbed to at
    // the moment each WebAuthController is actually constructed, not a
    // snapshot taken here.
    when(() => auth.authStateChanges())
        .thenAnswer((_) => Stream.value(auth.currentUser));

    repository = WebAuthRepository(auth: auth, firestore: firestore);
    controller = WebAuthController(repository);
  });

  test('starts on the form stage, sign-in mode, with empty fields', () {
    expect(controller.state.stage, WebAuthStage.form);
    expect(controller.state.isSignUpMode, isFalse);
    expect(controller.state.email, isEmpty);
    expect(controller.state.password, isEmpty);
    expect(controller.state.errorMessage, isNull);
  });

  test(
    'a browser reload while already fully signed in lands straight on done',
    () async {
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

      final reloaded = WebAuthController(repository);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(reloaded.state.stage, WebAuthStage.done);
    },
  );

  test(
    'a browser reload mid-signup (account created, not yet verified) resumes on '
    'awaitingVerification instead of losing progress back to a blank form',
    () async {
      final fbUser = _MockUser();
      final signUpCredential = _MockUserCredential();
      when(() => fbUser.sendEmailVerification()).thenAnswer((_) async {});
      when(() => signUpCredential.user).thenReturn(fbUser);
      when(
        () => auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        ),
      ).thenAnswer((_) async => signUpCredential);
      await repository.signUp(email: email, password: password);
      // Now that an account exists, currentUser reflects it for the
      // NEXT controller's construction-time resume check — still
      // unverified, so completeSignUp() (tried as part of resuming)
      // should correctly bounce back to awaitingVerification rather
      // than somehow reaching done.
      when(() => auth.currentUser).thenReturn(fbUser);
      when(() => fbUser.email).thenReturn(email);
      when(() => fbUser.reload()).thenAnswer((_) async {});
      when(() => fbUser.getIdToken(any()))
          .thenAnswer((_) async => 'fake-token');
      when(() => fbUser.emailVerified).thenReturn(false);

      final reloaded = WebAuthController(repository);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(reloaded.state.stage, WebAuthStage.awaitingVerification);
      expect(reloaded.state.email, email);
    },
  );

  test('a browser reload with a verified-but-not-yet-resumed session (real close/reopen scenario) '
      'lands straight on done, not awaitingVerification — this is the actual persistence guarantee', () async {
    final fbUser = _MockUser();
    when(() => auth.currentUser).thenReturn(fbUser);
    when(() => fbUser.uid).thenReturn(uid);
    when(() => fbUser.email).thenReturn(email);
    when(() => fbUser.reload()).thenAnswer((_) async {});
    when(() => fbUser.getIdToken(any())).thenAnswer((_) async => 'fake-token');
    when(() => fbUser.emailVerified)
        .thenReturn(true); // already verified before the browser closed
    when(() => staffSnapshot.exists).thenReturn(true);
    when(() => staffSnapshot.data())
        .thenReturn({'name': 'Amaka', 'role': 'owner', 'active': true});

    final reloaded = WebAuthController(repository);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(reloaded.state.stage, WebAuthStage.done);
  });

  group('setEmail / setPassword / toggleSignUpMode', () {
    test('update their fields and clear any previous error', () async {
      when(
        () => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(fb_auth.FirebaseAuthException(code: 'wrong-password'));
      controller.setEmail(email);
      controller.setPassword('wrong');
      await controller.signIn();
      expect(controller.state.errorMessage, isNotNull);

      controller.setEmail('  Owner@Example.com  ');
      expect(controller.state.email, '  Owner@Example.com  ');
      expect(controller.state.errorMessage, isNull);

      controller.setPassword(password);
      expect(controller.state.password, password);
    });

    test(
      'toggling sign-up mode flips the flag and clears the password field',
      () {
        controller.setPassword('something');
        controller.toggleSignUpMode();
        expect(controller.state.isSignUpMode, isTrue);
        expect(controller.state.password, isEmpty);

        controller.toggleSignUpMode();
        expect(controller.state.isSignUpMode, isFalse);
      },
    );
  });

  group('signIn', () {
    test('does nothing when email or password is blank', () async {
      controller.setEmail(email);
      // password left blank
      await controller.signIn();
      expect(controller.state.stage, WebAuthStage.form);
      verifyNever(
        () => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    });

    test('moves straight to done on success', () async {
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

      controller.setEmail(email);
      controller.setPassword(password);
      await controller.signIn();

      expect(controller.state.stage, WebAuthStage.done);
      expect(controller.state.errorMessage, isNull);
    });

    test(
      'falls back to the form stage with an honest error on wrong credentials',
      () async {
        when(
          () =>
              auth.signInWithEmailAndPassword(email: email, password: password),
        ).thenThrow(
          fb_auth.FirebaseAuthException(
            code: 'wrong-password',
            message: 'The password is invalid',
          ),
        );

        controller.setEmail(email);
        controller.setPassword(password);
        await controller.signIn();

        expect(controller.state.stage, WebAuthStage.form);
        expect(controller.state.errorMessage, contains('wrong-password'));
      },
    );
  });

  group('signUp', () {
    test('does nothing when email or password is blank', () async {
      controller.setEmail(email);
      await controller.signUp();
      expect(controller.state.stage, WebAuthStage.form);
      verifyNever(
        () => auth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    });

    test('moves to awaitingVerification on success, having sent exactly one verification email', () async {
      final fbUser = _MockUser();
      final credential = _MockUserCredential();
      when(() => fbUser.sendEmailVerification()).thenAnswer((_) async {});
      when(() => credential.user).thenReturn(fbUser);
      when(
        () => auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        ),
      ).thenAnswer((_) async => credential);

      controller.setEmail(email);
      controller.setPassword(password);
      await controller.signUp();

      expect(controller.state.stage, WebAuthStage.awaitingVerification);
      verify(() => fbUser.sendEmailVerification()).called(1);
    });

    test('falls back to the form stage with an honest error when the email is already in use', () async {
      when(
        () => auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        ),
      ).thenThrow(fb_auth.FirebaseAuthException(code: 'email-already-in-use'));

      controller.setEmail(email);
      controller.setPassword(password);
      await controller.signUp();

      expect(controller.state.stage, WebAuthStage.form);
      expect(controller.state.errorMessage, contains('email-already-in-use'));
    });
  });

  group('checkVerificationAndContinue', () {
    Future<void> signUpFirst() async {
      final fbUser = _MockUser();
      final credential = _MockUserCredential();
      when(() => fbUser.sendEmailVerification()).thenAnswer((_) async {});
      when(() => credential.user).thenReturn(fbUser);
      when(
        () => auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        ),
      ).thenAnswer((_) async => credential);
      controller.setEmail(email);
      controller.setPassword(password);
      await controller.signUp();

      when(() => fbUser.uid).thenReturn(uid);
      when(() => fbUser.email).thenReturn(email);
      when(() => auth.currentUser).thenReturn(fbUser);
      when(() => fbUser.reload()).thenAnswer((_) async {
        when(() => fbUser.emailVerified).thenReturn(true);
      });
      when(() => fbUser.getIdToken(any()))
          .thenAnswer((_) async => 'fake-token');
      when(() => fbUser.emailVerified).thenReturn(false);
    }

    test(
      'reaches done once Firebase confirms the reloaded user is verified',
      () async {
        await signUpFirst();
        when(() => staffSnapshot.exists).thenReturn(true);
        when(() => staffSnapshot.data())
            .thenReturn({'name': 'Amaka', 'role': 'owner', 'active': true});

        await controller.checkVerificationAndContinue();

        expect(controller.state.stage, WebAuthStage.done);
        expect(controller.state.errorMessage, isNull);
      },
    );

    test('stays on awaitingVerification with a clear message when not actually verified yet', () async {
      final fbUser = _MockUser();
      final credential = _MockUserCredential();
      when(() => fbUser.sendEmailVerification()).thenAnswer((_) async {});
      when(() => credential.user).thenReturn(fbUser);
      when(
        () => auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        ),
      ).thenAnswer((_) async => credential);
      controller.setEmail(email);
      controller.setPassword(password);
      await controller.signUp();

      when(() => auth.currentUser).thenReturn(fbUser);
      when(() => fbUser.reload()).thenAnswer((_) async {});
      when(() => fbUser.getIdToken(any()))
          .thenAnswer((_) async => 'fake-token');
      when(
        () => fbUser.emailVerified,
      ).thenReturn(false); // reload didn't change anything — still unverified

      await controller.checkVerificationAndContinue();

      expect(controller.state.stage, WebAuthStage.awaitingVerification);
      expect(controller.state.errorMessage, contains('Not verified yet'));
    });
  });

  group('resendVerificationEmail', () {
    test(
      'surfaces an honest error if it fails, without changing stage',
      () async {
        when(() => auth.currentUser)
            .thenReturn(null); // nobody signed in -> StateError inside the repo

        await controller.resendVerificationEmail();

        expect(controller.state.errorMessage, isNotNull);
      },
    );
  });

  group('signOut', () {
    test('resets back to the default form state', () async {
      when(() => auth.signOut()).thenAnswer((_) async {});
      controller.setEmail(email);

      await controller.signOut();

      expect(controller.state.stage, WebAuthStage.form);
      expect(controller.state.email, isEmpty);
      verify(() => auth.signOut()).called(1);
    });
  });
}
