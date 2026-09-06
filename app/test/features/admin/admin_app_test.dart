import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leumadepos/admin_app.dart';
import 'package:leumadepos/core/widgets/app_button.dart';
import 'package:leumadepos/features/admin/application/admin_auth_controller.dart';
import 'package:leumadepos/features/admin/application/admin_onboarding_controller.dart';
import 'package:leumadepos/features/admin/data/admin_auth_repository.dart';
import 'package:leumadepos/features/admin/data/business_onboarding_repository.dart';

/// The security half (only a seeded platform super-admin can create a
/// business or a business's first-owner invite; nobody else, ever) is
/// covered against a real Firestore emulator in
/// firestore_rules_tests/super_admin_rules.test.mjs — Dart widget tests
/// can't exercise real security rules. This file covers the other half:
/// AdminApp's own UI/state logic (sign-in flow, form validation, success/
/// error handling) against fake repositories.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // A web/desktop-sized surface, not the phone-sized default other test
  // files use — this is a browser tool, and the onboarding form's four
  // fields don't fit the framework's default 800x600 test surface.
  // tester.view.physicalSize (not the deprecated setSurfaceSize) also
  // updates MediaQuery correctly in this environment.
  void useDesktopSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Builds AdminApp with fakes, via an explicit ProviderContainer so
  /// tests can drive the sign-in-link completion directly (there's no
  /// real inbox/URL-reopen to simulate from widget taps alone).
  ({ProviderContainer container, Widget app}) buildAdminApp({
    FakeAdminAuthRepository? auth,
    FakeBusinessOnboardingRepository? onboarding,
  }) {
    final container = ProviderContainer(
      overrides: [
        adminAuthRepositoryProvider.overrideWithValue(auth ?? FakeAdminAuthRepository()),
        businessOnboardingRepositoryProvider.overrideWithValue(onboarding ?? FakeBusinessOnboardingRepository()),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, app: UncontrolledProviderScope(container: container, child: const AdminApp()));
  }

  testWidgets('shows the email form, then "check your email" after sending a link', (tester) async {
    final built = buildAdminApp();
    useDesktopSurface(tester);
    await tester.pumpWidget(built.app);
    await settle(tester);

    expect(find.text('Leumadepos admin'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'admin@example.com');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.text('Send link'));
    await settle(tester);

    expect(find.textContaining('Check your email'), findsOneWidget);
    expect(find.textContaining('admin@example.com'), findsOneWidget);
  });

  testWidgets('completing sign-in via the emailed link lands on the onboarding form', (tester) async {
    final auth = FakeAdminAuthRepository();
    final built = buildAdminApp(auth: auth);
    useDesktopSurface(tester);
    await tester.pumpWidget(built.app);
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'admin@example.com');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.text('Send link'));
    await settle(tester);

    final link = auth.lastSentLink;
    expect(link, isNotNull);

    await built.container
        .read(adminAuthControllerProvider.notifier)
        .completeSignInIfLinkPresent(link!);
    await settle(tester);

    expect(find.text('Onboard a business'), findsOneWidget);
  });

  group('onboarding form (already signed in)', () {
    Future<ProviderContainer> signIn(WidgetTester tester, {FakeBusinessOnboardingRepository? onboarding}) async {
      final auth = FakeAdminAuthRepository();
      final built = buildAdminApp(auth: auth, onboarding: onboarding);
      useDesktopSurface(tester);
    await tester.pumpWidget(built.app);
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'admin@example.com');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.text('Send link'));
      await settle(tester);

      await built.container
          .read(adminAuthControllerProvider.notifier)
          .completeSignInIfLinkPresent(auth.lastSentLink!);
      await settle(tester);
      return built.container;
    }

    testWidgets('Onboard button stays disabled until every field is valid', (tester) async {
      await signIn(tester);

      bool onboardButtonEnabled() =>
          tester.widget<AppButton>(find.widgetWithText(AppButton, 'Onboard business')).onPressed != null;

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(4));

      expect(onboardButtonEnabled(), isFalse);

      await tester.enterText(fields.at(0), 'bad slug!'); // invalid: space and punctuation
      await tester.enterText(fields.at(1), 'Some Business');
      await tester.enterText(fields.at(2), 'Some Owner');
      await tester.enterText(fields.at(3), 'owner@example.com');
      await tester.pump(const Duration(milliseconds: 10));

      expect(onboardButtonEnabled(), isFalse);
      expect(find.textContaining('Lowercase letters, digits'), findsOneWidget);

      await tester.enterText(fields.at(0), 'some-business');
      await tester.pump(const Duration(milliseconds: 10));

      expect(onboardButtonEnabled(), isTrue);
    });

    testWidgets('submitting onboards the business, shows success, and resets the form', (tester) async {
      final onboarding = FakeBusinessOnboardingRepository();
      await signIn(tester, onboarding: onboarding);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'new-biz');
      await tester.enterText(fields.at(1), 'New Biz Ltd');
      await tester.enterText(fields.at(2), 'Jane Owner');
      await tester.enterText(fields.at(3), 'jane@example.com');
      await tester.pump(const Duration(milliseconds: 10));

      await tester.tap(find.text('Onboard business'));
      await settle(tester);

      expect(find.textContaining('"new-biz" created'), findsOneWidget);
      expect(find.textContaining('jane@example.com'), findsWidgets);

      expect(onboarding.onboarded, hasLength(1));
      expect(onboarding.onboarded.single.businessId, 'new-biz');
      expect(onboarding.onboarded.single.ownerEmail, 'jane@example.com');

      // Fields cleared after success.
      for (final field in tester.widgetList<TextField>(fields)) {
        expect(field.controller!.text, isEmpty);
      }
    });

    testWidgets('shows a clear error when the business ID is already taken', (tester) async {
      final onboarding = FakeBusinessOnboardingRepository();
      await onboarding.onboardBusiness(
        businessId: 'taken-biz',
        businessName: 'Existing',
        ownerName: 'Existing Owner',
        ownerEmail: 'existing@example.com',
      );
      await signIn(tester, onboarding: onboarding);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'taken-biz');
      await tester.enterText(fields.at(1), 'New Biz Ltd');
      await tester.enterText(fields.at(2), 'Jane Owner');
      await tester.enterText(fields.at(3), 'jane@example.com');
      await tester.pump(const Duration(milliseconds: 10));

      await tester.tap(find.text('Onboard business'));
      await settle(tester);

      expect(find.text('That business ID is already taken — pick another.'), findsOneWidget);
    });
  });
}
