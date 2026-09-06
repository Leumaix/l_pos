import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:leumadepos/features/auth/data/auth_repository.dart';
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

class _MockWriteBatch extends Mock implements WriteBatch {}

void main() {
  setUpAll(() {
    // mocktail needs a real dummy instance for any() used against a
    // named, non-nullable, non-primitive parameter type — a pure
    // registration, never actually sent anywhere.
    registerFallbackValue(fb_auth.ActionCodeSettings(url: 'https://example.com'));
    registerFallbackValue(_MockDocumentReference());
  });

  late _MockFirebaseAuth auth;
  late _MockFirebaseFirestore firestore;
  late _MockDocumentReference staffRef;
  late _MockDocumentReference inviteRef;
  late _MockDocumentSnapshot staffSnapshot;
  late _MockDocumentSnapshot inviteSnapshot;
  late _MockWriteBatch batch;
  late InMemoryCredentialStore store;
  late WebAuthRepository repository;

  const uid = 'uid-1';
  const email = 'owner@example.com';
  const link = 'https://example.com/?apiKey=x&mode=signIn&oobCode=y';

  setUp(() {
    auth = _MockFirebaseAuth();
    firestore = _MockFirebaseFirestore();
    staffRef = _MockDocumentReference();
    inviteRef = _MockDocumentReference();
    staffSnapshot = _MockDocumentSnapshot();
    inviteSnapshot = _MockDocumentSnapshot();
    batch = _MockWriteBatch();
    store = InMemoryCredentialStore();

    when(() => firestore.doc('businesses/ph-zazaa/staff/$uid')).thenReturn(staffRef);
    when(() => firestore.doc('businesses/ph-zazaa/invites/$email')).thenReturn(inviteRef);
    when(() => staffRef.get()).thenAnswer((_) async => staffSnapshot);
    when(() => inviteRef.get()).thenAnswer((_) async => inviteSnapshot);
    when(() => firestore.batch()).thenReturn(batch);
    when(() => batch.set(any(), any())).thenReturn(null);
    when(() => batch.delete(any())).thenReturn(null);
    when(() => batch.commit()).thenAnswer((_) async {});

    repository = WebAuthRepository(auth: auth, firestore: firestore, store: store);
  });

  group('sendVerificationLink', () {
    test('normalizes the email, sends a real link, and remembers it as pending', () async {
      when(() => auth.sendSignInLinkToEmail(
            email: any(named: 'email'),
            actionCodeSettings: any(named: 'actionCodeSettings'),
          )).thenAnswer((_) async {});

      await repository.sendVerificationLink('  Owner@Example.com  ');

      verify(() => auth.sendSignInLinkToEmail(
            email: 'owner@example.com',
            actionCodeSettings: any(named: 'actionCodeSettings'),
          )).called(1);
      expect(await repository.pendingVerificationEmail(), 'owner@example.com');
    });
  });

  group('isSignInWithEmailLink', () {
    test('delegates straight to the underlying Firebase Auth check', () {
      when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
      expect(repository.isSignInWithEmailLink(link), isTrue);

      when(() => auth.isSignInWithEmailLink('not-a-link')).thenReturn(false);
      expect(repository.isSignInWithEmailLink('not-a-link'), isFalse);
    });
  });

  group('completeEmailLinkSignIn', () {
    test('rejects a link that is not actually a sign-in link, without ever calling signInWithEmailLink', () async {
      when(() => auth.isSignInWithEmailLink(link)).thenReturn(false);

      await expectLater(
        () => repository.completeEmailLinkSignIn(email: email, emailLink: link),
        throwsA(isA<InvalidCredentialsException>()),
      );
      verifyNever(() => auth.signInWithEmailLink(email: any(named: 'email'), emailLink: any(named: 'emailLink')));
    });

    test('completes into a real AppUser and activates the session when the staff doc already exists', () async {
      final credential = _MockUserCredential();
      final fbUser = _MockUser();
      when(() => fbUser.uid).thenReturn(uid);
      when(() => credential.user).thenReturn(fbUser);
      when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
      when(() => auth.signInWithEmailLink(email: email, emailLink: link)).thenAnswer((_) async => credential);

      when(() => staffSnapshot.exists).thenReturn(true);
      when(() => staffSnapshot.data()).thenReturn({
        'name': 'Amaka',
        'role': 'owner',
        'active': true,
        'phone': '08000000000',
      });

      expect(repository.currentUser, isNull);
      expect(repository.activeFirestore, isNull);

      await repository.completeEmailLinkSignIn(email: email, emailLink: link);

      expect(repository.currentUser?.uid, uid);
      expect(repository.currentUser?.name, 'Amaka');
      expect(repository.currentUser?.role, 'owner');
      expect(repository.currentUser?.phone, '08000000000');
      expect(repository.activeFirestore, same(firestore));
      // No PIN step here — completing the link IS the whole sign-in.
      expect(await repository.pendingVerificationEmail(), isNull);
    });

    test('emits the newly signed-in user on authStateChanges', () async {
      final credential = _MockUserCredential();
      final fbUser = _MockUser();
      when(() => fbUser.uid).thenReturn(uid);
      when(() => credential.user).thenReturn(fbUser);
      when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
      when(() => auth.signInWithEmailLink(email: email, emailLink: link)).thenAnswer((_) async => credential);
      when(() => staffSnapshot.exists).thenReturn(true);
      when(() => staffSnapshot.data()).thenReturn({'name': 'Amaka', 'role': 'owner', 'active': true});

      final emissions = <AppUser?>[];
      final sub = repository.authStateChanges().listen(emissions.add);
      await Future<void>.delayed(Duration.zero);

      await repository.completeEmailLinkSignIn(email: email, emailLink: link);
      await Future<void>.delayed(Duration.zero);

      expect(emissions.first, isNull); // the initial "nobody signed in" replay
      expect(emissions.last?.uid, uid);
      await sub.cancel();
    });

    test(
      'self-provisions via a matching owner-issued invite when no staff doc exists yet, '
      'atomically creating the staff doc and consuming the invite',
      () async {
        final credential = _MockUserCredential();
        final fbUser = _MockUser();
        when(() => fbUser.uid).thenReturn(uid);
        when(() => credential.user).thenReturn(fbUser);
        when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
        when(() => auth.signInWithEmailLink(email: email, emailLink: link)).thenAnswer((_) async => credential);

        when(() => staffSnapshot.exists).thenReturn(false);
        when(() => staffSnapshot.data()).thenReturn(null);
        when(() => inviteSnapshot.exists).thenReturn(true);
        when(() => inviteSnapshot.data()).thenReturn({'name': 'First Owner', 'role': 'owner'});

        await repository.completeEmailLinkSignIn(email: email, emailLink: link);

        expect(repository.currentUser?.name, 'First Owner');
        expect(repository.currentUser?.role, 'owner');
        expect(repository.currentUser?.phone, isNull); // never supplied by an invite
        verify(() => batch.set(staffRef, {'name': 'First Owner', 'role': 'owner', 'active': true})).called(1);
        verify(() => batch.delete(inviteRef)).called(1);
        verify(() => batch.commit()).called(1);
      },
    );

    test('throws StaffRecordNotFoundException when there is no staff doc AND no matching invite', () async {
      final credential = _MockUserCredential();
      final fbUser = _MockUser();
      when(() => fbUser.uid).thenReturn(uid);
      when(() => credential.user).thenReturn(fbUser);
      when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
      when(() => auth.signInWithEmailLink(email: email, emailLink: link)).thenAnswer((_) async => credential);

      when(() => staffSnapshot.exists).thenReturn(false);
      when(() => staffSnapshot.data()).thenReturn(null);
      when(() => inviteSnapshot.exists).thenReturn(false);
      when(() => inviteSnapshot.data()).thenReturn(null);

      await expectLater(
        () => repository.completeEmailLinkSignIn(email: email, emailLink: link),
        throwsA(isA<StaffRecordNotFoundException>()),
      );
      expect(repository.currentUser, isNull);
      verifyNever(() => batch.commit());
    });

    test('throws StaffRecordNotFoundException for a deactivated staff member, never falling through to self-provisioning', () async {
      final credential = _MockUserCredential();
      final fbUser = _MockUser();
      when(() => fbUser.uid).thenReturn(uid);
      when(() => credential.user).thenReturn(fbUser);
      when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
      when(() => auth.signInWithEmailLink(email: email, emailLink: link)).thenAnswer((_) async => credential);

      when(() => staffSnapshot.exists).thenReturn(true);
      when(() => staffSnapshot.data()).thenReturn({'name': 'Amaka', 'role': 'owner', 'active': false});

      await expectLater(
        () => repository.completeEmailLinkSignIn(email: email, emailLink: link),
        throwsA(isA<StaffRecordNotFoundException>()),
      );
      verifyNever(() => inviteRef.get());
    });
  });

  group('PIN-only methods — never meaningful on the web build', () {
    test('isDeviceVerifiedFor throws UnsupportedError', () {
      expect(() => repository.isDeviceVerifiedFor(email), throwsUnsupportedError);
    });

    test('signInWithEmailAndPin throws UnsupportedError', () {
      expect(() => repository.signInWithEmailAndPin(email: email, pin: '1234'), throwsUnsupportedError);
    });

    test('setPinForVerifiedDevice throws UnsupportedError', () {
      expect(() => repository.setPinForVerifiedDevice(email: email, pin: '1234'), throwsUnsupportedError);
    });
  });

  group('signOut', () {
    test('really signs out of Firebase (unlike the mobile flow) and clears the session', () async {
      when(() => auth.signOut()).thenAnswer((_) async {});
      // Fake an active session directly via a successful sign-in first.
      final credential = _MockUserCredential();
      final fbUser = _MockUser();
      when(() => fbUser.uid).thenReturn(uid);
      when(() => credential.user).thenReturn(fbUser);
      when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
      when(() => auth.signInWithEmailLink(email: email, emailLink: link)).thenAnswer((_) async => credential);
      when(() => staffSnapshot.exists).thenReturn(true);
      when(() => staffSnapshot.data()).thenReturn({'name': 'Amaka', 'role': 'owner', 'active': true});
      await repository.completeEmailLinkSignIn(email: email, emailLink: link);
      expect(repository.currentUser, isNotNull);

      await repository.signOut();

      verify(() => auth.signOut()).called(1);
      expect(repository.currentUser, isNull);
      expect(repository.activeFirestore, isNull);
    });
  });
}
