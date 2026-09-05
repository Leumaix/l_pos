import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/auth/presentation/login_screen.dart';

/// Wide-mode coverage for the real Login screen (not just the generic
/// KeypadEntryLayout it's built on — see keypad_entry_layout_test.dart for
/// that). This is the screen the original landscape bug was reported
/// against: "Sign In" scrolled off below the keypad on the Itel tablet.
/// Narrow mode (single stacked column) is unchanged from before Tier 2 and
/// already covered elsewhere via the login flow tests.
void main() {
  // AppButton renders an indeterminate CircularProgressIndicator while
  // state.submitting is true, whose repeating animation controller keeps
  // scheduling new frames — pumpAndSettle() would loop forever waiting for
  // a "settled" tree that never arrives. Use a bounded pump loop instead,
  // same pattern as verify_email_flow_test.dart.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget harness() {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LoginScreen()),
    );
  }

  testWidgets(
    'wide: at the real Itel tablet landscape size, Sign In and the email/PIN '
    'field stay in the same pane as each other, strictly left of the keypad, '
    'and Sign In never sits below the keypad',
    (tester) async {
      // Same real dimensions used throughout the Tier 1/2 landscape
      // regression tests — see gas_numpad_sheet_test.dart.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Sign In stays within the viewport with no scrolling required to
      // reach it — the original bug report.
      final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final signInRect = tester.getRect(find.text('Sign in'));
      expect(signInRect.bottom, lessThanOrEqualTo(screenHeight));

      // The defining property of the wide split: the email field and Sign
      // In both sit in the same (left) pane, strictly left of the keypad's
      // pane — not below it, which is what the bug actually was.
      final emailFieldX = tester.getTopLeft(find.byType(TextField)).dx;
      final signInX = tester.getTopLeft(find.text('Sign in')).dx;
      final keypadX = tester.getTopLeft(find.text('1')).dx;
      expect(emailFieldX, lessThan(keypadX));
      expect(signInX, lessThan(keypadX));

      // The full flow still works end to end in this layout: type an email,
      // tap out a PIN on the real NumericKeypad, and Sign In actually
      // submits (FakeAuthRepository's seeded owner).
      await tester.enterText(find.byType(TextField), 'chidi@leumadepos.test');
      await tester.pump();
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      expect(find.text('Sign in'), findsOneWidget);
      // AppButton's label sits directly inside its InkWell, so tapping the
      // text hits the button.
      await tester.tap(find.text('Sign in'));
      await settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);
    },
  );
}
