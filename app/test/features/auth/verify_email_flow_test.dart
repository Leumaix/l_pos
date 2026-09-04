import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leumadepos/app.dart';
import 'package:leumadepos/core/widgets/pin_dots.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/application/verification_controller.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/auth/presentation/verify_email_screen.dart';
import 'package:leumadepos/features/customers/application/customer_providers.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/application/sales_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/data/sales_repository.dart';

/// Exercises the first-time-verification/switcher flow end to end through
/// real widgets and the real VerificationController — everything EXCEPT
/// the actual native email-link deep link, which this sandbox can't
/// produce (no real device/mailbox). That one step is simulated by
/// calling the controller directly, exactly as main.dart's app_links
/// listener would once a real link arrives; every other step (routing,
/// PIN entry/confirmation, mismatch handling, landing on Home) is real.
Widget _appWithFakeAuth() {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      salesRepositoryProvider.overrideWithValue(FakeSalesRepository()),
      customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
    ],
    child: const LeumadeposApp(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> useDefaultPhoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // A bounded stand-in for pumpAndSettle: this app has a couple of
  // legitimately-indeterminate animations in flight during this flow
  // (button loading spinners), which never let pumpAndSettle itself
  // detect a "settled" tree. Pumping a fixed number of frames covering
  // well over any real async delay in this flow (longest is 300ms) is
  // deterministic and side-steps that entirely.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'first-time verification: Login -> send link -> (link arrives) -> choose PIN -> confirm -> lands on Home',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      await tester.pumpWidget(_appWithFakeAuth());
      await settle(tester);

      // Narrow but tall content — the footer link can sit below the
      // fold; ensureVisible scrolls it into reach before tapping,
      // same as a real user would.
      await tester.ensureVisible(
        find.text('First time on this device? Verify by email'),
      );
      await tester.tap(find.text('First time on this device? Verify by email'));
      await settle(tester);

      expect(find.byType(VerifyEmailScreen), findsOneWidget);
      expect(find.text('Verify this device'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'chidi@leumadepos.test');
      // A bare, no-duration pump() right after enterText deadlocks here
      // (the newly-focused field's caret-blink scheduling appears to
      // interact badly with it) — a durational pump avoids it, same as
      // settle() does everywhere else in this test.
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.text('Send link'));
      await settle(tester);

      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('chidi@leumadepos.test'), findsOneWidget);

      // Simulate the deep link arriving (see the doc comment above).
      final context = tester.element(find.byType(VerifyEmailScreen));
      final container = ProviderScope.containerOf(context);
      // Not awaited directly: this binding's clock only advances via
      // tester.pump(duration), so awaiting an async repository call here
      // (with its own internal delay) would deadlock before settle()
      // ever gets a chance to advance the clock for it.
      // ignore: unawaited_futures
      container
          .read(verificationControllerProvider.notifier)
          .handleIncomingLink('fake-link');
      await settle(tester);

      expect(find.text('Choose a 4-digit PIN'), findsOneWidget);

      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await settle(tester);

      expect(find.text('Confirm your PIN'), findsOneWidget);
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 0);

      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await settle(tester);

      // Router redirect fires automatically once the fake repository's
      // auth-state stream flips currentUser non-null.
      expect(find.text('Chidi (Owner)'), findsOneWidget);
      expect(find.text('Quick actions'), findsOneWidget);
    },
  );

  testWidgets('PIN confirmation mismatch clears both entries and asks again', (
    tester,
  ) async {
    await useDefaultPhoneSurface(tester);
    await tester.pumpWidget(_appWithFakeAuth());
    await settle(tester);

    // Narrow but tall content — the footer link can sit below the
    // fold; ensureVisible scrolls it into reach before tapping,
    // same as a real user would.
    await tester.ensureVisible(
      find.text('First time on this device? Verify by email'),
    );
    await tester.tap(find.text('First time on this device? Verify by email'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'chidi@leumadepos.test');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.text('Send link'));
    await settle(tester);

    final context = tester.element(find.byType(VerifyEmailScreen));
    final container = ProviderScope.containerOf(context);
    // ignore: unawaited_futures
    container
        .read(verificationControllerProvider.notifier)
        .handleIncomingLink('fake-link');
    await settle(tester);

    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await settle(tester);
    expect(find.text('Confirm your PIN'), findsOneWidget);

    for (final digit in ['9', '9', '9', '9']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await settle(tester);

    expect(find.text('PINs didn\'t match — try again.'), findsOneWidget);
    expect(find.text('Choose a 4-digit PIN'), findsOneWidget);
    expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 0);
  });

  testWidgets(
    'email-link sign-in for an unregistered email shows a clear "not set up" message, not a retry loop',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      await tester.pumpWidget(_appWithFakeAuth());
      await settle(tester);

      // Narrow but tall content — the footer link can sit below the
      // fold; ensureVisible scrolls it into reach before tapping,
      // same as a real user would.
      await tester.ensureVisible(
        find.text('First time on this device? Verify by email'),
      );
      await tester.tap(find.text('First time on this device? Verify by email'));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'stranger@example.com');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.text('Send link'));
      await settle(tester);

      final context = tester.element(find.byType(VerifyEmailScreen));
      final container = ProviderScope.containerOf(context);
      // ignore: unawaited_futures
      container
          .read(verificationControllerProvider.notifier)
          .handleIncomingLink('fake-link');
      await settle(tester);

      // Real ownership of the email was proven (a real link was sent and
      // opened) but there's no staff record for it — a clear, honest
      // message, not the old generic "Could not save the PIN" retry loop.
      expect(find.text('This device isn\'t set up for you'), findsOneWidget);

      await tester.tap(find.text('Try a different email'));
      await settle(tester);

      expect(find.text('Verify this device'), findsOneWidget);
    },
  );

  testWidgets(
    'a second staff member verifying this device does not disturb another staff member\'s active session (handoff, not auto-switch)',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      await tester.pumpWidget(_appWithFakeAuth());
      await settle(tester);

      // Chidi signs in first.
      await tester.enterText(find.byType(TextField), 'chidi@leumadepos.test');
      await tester.pump(const Duration(milliseconds: 10));
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.tap(find.text('Sign in'));
      await settle(tester);

      expect(find.text('Chidi (Owner)'), findsOneWidget);

      // Ifeoma starts her own one-time device verification from Home's
      // account menu, without Chidi signing out — this is the ONLY way a
      // second staff member can reach /verify-email while someone's
      // already active on this shared device.
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await settle(tester);
      await tester.tap(find.text('Verify another staff member'));
      await settle(tester);

      expect(find.byType(VerifyEmailScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ifeoma@leumadepos.test');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.text('Send link'));
      await settle(tester);

      final context = tester.element(find.byType(VerifyEmailScreen));
      final container = ProviderScope.containerOf(context);
      // ignore: unawaited_futures
      container
          .read(verificationControllerProvider.notifier)
          .handleIncomingLink('fake-link');
      await settle(tester);

      expect(find.text('Choose a 4-digit PIN'), findsOneWidget);

      for (final digit in ['1', '1', '1', '1']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await settle(tester);
      for (final digit in ['1', '1', '1', '1']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await settle(tester);

      // Landed on the handoff message, naming who's currently active —
      // not silently switched to Ifeoma, not bounced to Chidi's Home.
      expect(find.text('Setup complete'), findsOneWidget);
      expect(find.textContaining('Chidi (Owner)'), findsOneWidget);

      // The whole point of the guard: Chidi's session is untouched.
      expect(
        container.read(authRepositoryProvider).currentUser?.name,
        'Chidi (Owner)',
      );
    },
  );
}
