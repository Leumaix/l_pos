import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/application/web_auth_controller.dart';
import 'package:leumadepos/features/auth/data/local_credential_store.dart';
import 'package:leumadepos/features/auth/data/web_auth_repository.dart';
import 'package:leumadepos/features/customers/application/customer_providers.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/application/sales_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/data/sales_repository.dart';
import 'package:leumadepos/features/shift/application/shift_providers.dart';
import 'package:leumadepos/features/shift/data/shift_repository.dart';
import 'package:leumadepos/web_app.dart';

class _MockFirebaseAuth extends Mock implements fb_auth.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb_auth.UserCredential {}

class _MockUser extends Mock implements fb_auth.User {}

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

/// Same style/goal as shift_gating_router_test.dart, but proving the
/// WEB router specifically: WebLoginScreen at /login instead of the PIN
/// keypad, and that the same owner-only/shift-gating redirect rules
/// still hold once signed in through the plain email-link flow — none
/// of that logic is auth-scheme-specific, so it should behave exactly
/// like the mobile router's.
void main() {
  setUpAll(() {
    registerFallbackValue(fb_auth.ActionCodeSettings(url: 'https://example.com'));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  const uid = 'uid-1';
  const email = 'owner@example.com';
  const link = 'https://example.com/?apiKey=x&mode=signIn&oobCode=y';

  late _MockFirebaseAuth auth;
  late _MockFirebaseFirestore firestore;
  late _MockDocumentReference staffRef;
  late _MockDocumentSnapshot staffSnapshot;
  late WebAuthRepository webAuthRepo;

  Widget appWithFakes({required FakeShiftRepository shift, required String role}) {
    when(() => firestore.doc('businesses/ph-zazaa/staff/$uid')).thenReturn(staffRef);
    when(() => staffRef.get()).thenAnswer((_) async => staffSnapshot);
    when(() => staffSnapshot.exists).thenReturn(true);
    when(() => staffSnapshot.data()).thenReturn({'name': 'Amaka', 'role': role, 'active': true});

    return ProviderScope(
      overrides: [
        webAuthRepositoryProvider.overrideWithValue(webAuthRepo),
        authRepositoryProvider.overrideWith((ref) => ref.watch(webAuthRepositoryProvider)),
        // Same fakes shift_gating_router_test.dart uses for the mobile
        // router — dashboardSummaryProvider reads through these, never
        // through the mocked Firestore above, so Home renders safely.
        inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
        salesRepositoryProvider.overrideWithValue(FakeSalesRepository()),
        customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
        shiftRepositoryProvider.overrideWithValue(shift),
      ],
      child: const WebApp(),
    );
  }

  Future<void> signIn(WidgetTester tester) async {
    when(() => auth.sendSignInLinkToEmail(
          email: any(named: 'email'),
          actionCodeSettings: any(named: 'actionCodeSettings'),
        )).thenAnswer((_) async {});
    await tester.enterText(find.byType(TextField), email);
    await tester.pump(); // let onChanged rebuild the form before checking the button is enabled
    await tester.tap(find.text('Send link'));
    await settle(tester);

    final credential = _MockUserCredential();
    final fbUser = _MockUser();
    when(() => fbUser.uid).thenReturn(uid);
    when(() => credential.user).thenReturn(fbUser);
    when(() => auth.isSignInWithEmailLink(link)).thenReturn(true);
    when(() => auth.signInWithEmailLink(email: email, emailLink: link)).thenAnswer((_) async => credential);

    // The real trigger is a browser reload with the link in the URL —
    // there's no in-app UI for it, same as admin_app_test.dart calls
    // completeSignInIfLinkPresent directly rather than simulating a
    // reload.
    final context = tester.element(find.byType(Scaffold).first);
    await ProviderScope.containerOf(context)
        .read(webAuthControllerProvider.notifier)
        .completeSignInIfLinkPresent(link);
    await settle(tester);
  }

  setUp(() {
    auth = _MockFirebaseAuth();
    firestore = _MockFirebaseFirestore();
    staffRef = _MockDocumentReference();
    staffSnapshot = _MockDocumentSnapshot();
    webAuthRepo = WebAuthRepository(auth: auth, firestore: firestore, store: InMemoryCredentialStore());

    // WebApp.initState() checks Uri.base.toString() against
    // isSignInWithEmailLink on every single pump, for whatever arbitrary
    // URI the test environment happens to report — false by default;
    // signIn() below overrides it specifically for the real test link.
    when(() => auth.isSignInWithEmailLink(any())).thenReturn(false);
  });

  testWidgets('an unauthenticated visitor sees WebLoginScreen (plain email field), not the PIN keypad', (tester) async {
    final shift = FakeShiftRepository(openShift: false);
    await tester.pumpWidget(appWithFakes(shift: shift, role: 'owner'));
    await settle(tester);

    expect(find.text('Sign in with your work email.'), findsOneWidget);
    expect(find.text('Send link'), findsOneWidget);
    expect(find.byIcon(Icons.dialpad), findsNothing); // no PIN keypad anywhere on this build
  });

  testWidgets('signing in via the email link reaches Home, reusing the exact same screen as mobile', (tester) async {
    final shift = FakeShiftRepository(openShift: false);
    await tester.pumpWidget(appWithFakes(shift: shift, role: 'owner'));
    await settle(tester);

    await signIn(tester);

    expect(find.text('Quick actions'), findsOneWidget);
  });

  testWidgets('an attendant is bounced away from /stock (owner-only) — same rule as the mobile router', (tester) async {
    final shift = FakeShiftRepository(openShift: false);
    await tester.pumpWidget(appWithFakes(shift: shift, role: 'attendant'));
    await settle(tester);
    await signIn(tester);

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/stock');
    await settle(tester);

    expect(find.text('Quick actions'), findsOneWidget); // bounced back to Home, never reached Stock
  });

  testWidgets('navigating to /sell with no shift open is redirected to Home — same rule as the mobile router', (tester) async {
    final shift = FakeShiftRepository(openShift: false);
    await tester.pumpWidget(appWithFakes(shift: shift, role: 'owner'));
    await settle(tester);
    await signIn(tester);

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/sell');
    await settle(tester);

    expect(find.text('The day hasn\'t been opened yet'), findsOneWidget);
    expect(find.text('Cart'), findsNothing);
  });

  testWidgets('navigating to /sell with a shift open reaches Sell normally', (tester) async {
    final shift = FakeShiftRepository(); // openShift: true by default
    await tester.pumpWidget(appWithFakes(shift: shift, role: 'owner'));
    await settle(tester);
    await signIn(tester);

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/sell');
    await settle(tester);

    expect(find.text('Cart'), findsOneWidget);
  });

  testWidgets(
    'Home\'s account menu never offers "Verify another staff member" on the web build — '
    'that shared-device handoff concept, and its /verify-email route, don\'t exist here',
    (tester) async {
      final shift = FakeShiftRepository(openShift: false);
      await tester.pumpWidget(appWithFakes(shift: shift, role: 'owner'));
      await settle(tester);
      await signIn(tester);

      await tester.tap(find.byTooltip('Account'));
      await settle(tester);

      expect(find.text('Sign out'), findsOneWidget); // the menu did open
      expect(find.text('Verify another staff member'), findsNothing);
    },
  );
}
