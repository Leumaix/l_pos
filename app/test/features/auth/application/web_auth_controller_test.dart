import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:leumadepos/features/auth/application/web_auth_controller.dart';
import 'package:leumadepos/features/auth/data/local_credential_store.dart';
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
    registerFallbackValue(fb_auth.ActionCodeSettings(url: 'https://example.com'));
  });

  late _MockFirebaseAuth auth;
  late _MockFirebaseFirestore firestore;
  late _MockDocumentReference staffRef;
  late _MockDocumentSnapshot staffSnapshot;
  late WebAuthRepository repository;
  late WebAuthController controller;

  const uid = 'uid-1';
  const email = 'owner@example.com';
  const link = 'https://example.com/?apiKey=x&mode=signIn&oobCode=y';

  setUp(() {
    auth = _MockFirebaseAuth();
    firestore = _MockFirebaseFirestore();
    staffRef = _MockDocumentReference();
    staffSnapshot = _MockDocumentSnapshot();

    when(() => firestore.doc('businesses/ph-zazaa/staff/$uid')).thenReturn(staffRef);
    when(() => staffRef.get()).thenAnswer((_) async => staffSnapshot);

    repository = WebAuthRepository(auth: auth, firestore: firestore, store: InMemoryCredentialStore());
    controller = WebAuthController(repository);
  });

  test('starts on the form stage with an empty email', () {
    expect(controller.state.stage, WebAuthStage.form);
    expect(controller.state.email, isEmpty);
    expect(controller.state.errorMessage, isNull);
  });

  test('a browser reload while already signed in lands straight on done', () async {
    when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
    final credential = _MockUserCredential();
    final fbUser = _MockUser();
    when(() => fbUser.uid).thenReturn(uid);
    when(() => credential.user).thenReturn(fbUser);
    when(() => auth.signInWithEmailLink(email: email, emailLink: link)).thenAnswer((_) async => credential);
    when(() => staffSnapshot.exists).thenReturn(true);
    when(() => staffSnapshot.data()).thenReturn({'name': 'Amaka', 'role': 'owner', 'active': true});
    await repository.completeEmailLinkSignIn(email: email, emailLink: link);

    // A second controller constructed against the same, already-signed-in
    // repository — mirrors WebAuthController's constructor check.
    final reloaded = WebAuthController(repository);
    expect(reloaded.state.stage, WebAuthStage.done);
  });

  group('setEmail', () {
    test('updates the email and clears any previous error', () async {
      // Produce a real error first, through the controller's own public
      // API, rather than poking at its protected state directly.
      when(() => auth.sendSignInLinkToEmail(
            email: any(named: 'email'),
            actionCodeSettings: any(named: 'actionCodeSettings'),
          )).thenThrow(Exception('network unreachable'));
      controller.setEmail(email);
      await controller.sendLink();
      expect(controller.state.errorMessage, isNotNull);

      controller.setEmail('  Owner@Example.com  ');

      expect(controller.state.email, '  Owner@Example.com  ');
      expect(controller.state.errorMessage, isNull);
    });
  });

  group('sendLink', () {
    test('does nothing for a blank email', () async {
      controller.setEmail('   ');
      await controller.sendLink();
      expect(controller.state.stage, WebAuthStage.form);
      verifyNever(() => auth.sendSignInLinkToEmail(
            email: any(named: 'email'),
            actionCodeSettings: any(named: 'actionCodeSettings'),
          ));
    });

    test('moves to linkSent on success', () async {
      when(() => auth.sendSignInLinkToEmail(
            email: any(named: 'email'),
            actionCodeSettings: any(named: 'actionCodeSettings'),
          )).thenAnswer((_) async {});

      controller.setEmail(email);
      await controller.sendLink();

      expect(controller.state.stage, WebAuthStage.linkSent);
      expect(controller.state.errorMessage, isNull);
    });

    test('falls back to the form stage with an honest error message on failure', () async {
      when(() => auth.sendSignInLinkToEmail(
            email: any(named: 'email'),
            actionCodeSettings: any(named: 'actionCodeSettings'),
          )).thenThrow(Exception('network unreachable'));

      controller.setEmail(email);
      await controller.sendLink();

      expect(controller.state.stage, WebAuthStage.form);
      expect(controller.state.errorMessage, contains('network unreachable'));
    });
  });

  group('completeSignInIfLinkPresent', () {
    test('is a no-op for an ordinary fresh page load (not a sign-in link)', () async {
      when(() => auth.isSignInWithEmailLink('https://example.com/')).thenReturn(false);

      await controller.completeSignInIfLinkPresent('https://example.com/');

      expect(controller.state.stage, WebAuthStage.form);
      expect(controller.state.errorMessage, isNull);
    });

    test('surfaces a clear error when no pending email is remembered on this browser', () async {
      when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
      // Deliberately never called sendLink first — no pending email saved.

      await controller.completeSignInIfLinkPresent(link);

      expect(controller.state.stage, WebAuthStage.form);
      expect(controller.state.errorMessage, contains('No pending sign-in email'));
      verifyNever(() => auth.signInWithEmailLink(email: any(named: 'email'), emailLink: any(named: 'emailLink')));
    });

    test('completes sign-in and reaches done when a link arrives for a real pending email', () async {
      when(() => auth.sendSignInLinkToEmail(
            email: any(named: 'email'),
            actionCodeSettings: any(named: 'actionCodeSettings'),
          )).thenAnswer((_) async {});
      controller.setEmail(email);
      await controller.sendLink();
      expect(controller.state.stage, WebAuthStage.linkSent);

      when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
      final credential = _MockUserCredential();
      final fbUser = _MockUser();
      when(() => fbUser.uid).thenReturn(uid);
      when(() => credential.user).thenReturn(fbUser);
      when(() => auth.signInWithEmailLink(email: email, emailLink: link)).thenAnswer((_) async => credential);
      when(() => staffSnapshot.exists).thenReturn(true);
      when(() => staffSnapshot.data()).thenReturn({'name': 'Amaka', 'role': 'owner', 'active': true});

      await controller.completeSignInIfLinkPresent(link);

      expect(controller.state.stage, WebAuthStage.done);
      expect(controller.state.errorMessage, isNull);
    });

    test('falls back to the form stage with an honest error for an invalid/expired link', () async {
      when(() => auth.sendSignInLinkToEmail(
            email: any(named: 'email'),
            actionCodeSettings: any(named: 'actionCodeSettings'),
          )).thenAnswer((_) async {});
      controller.setEmail(email);
      await controller.sendLink();

      when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
      when(() => auth.signInWithEmailLink(email: email, emailLink: link))
          .thenThrow(fb_auth.FirebaseAuthException(code: 'invalid-action-code'));

      await controller.completeSignInIfLinkPresent(link);

      expect(controller.state.stage, WebAuthStage.form);
      expect(controller.state.errorMessage, contains('invalid or expired'));
    });
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
