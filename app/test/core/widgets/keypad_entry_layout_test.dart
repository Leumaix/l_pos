import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/core/widgets/keypad_entry_layout.dart';

void main() {
  Widget harness({ValueChanged<String>? onKeyTap, VoidCallback? onSubmit}) => MaterialApp(
    home: Scaffold(
      body: KeypadEntryLayout(
        display: const Text('display'),
        keypad: const SizedBox(height: 300, width: 300, child: Text('keypad')),
        action: const Text('action'),
        onKeyTap: onKeyTap ?? (_) {},
        onSubmit: onSubmit,
      ),
    ),
  );

  testWidgets('narrow: stacks display, keypad, then action in one column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('display'), findsOneWidget);
    expect(find.text('keypad'), findsOneWidget);
    expect(find.text('action'), findsOneWidget);

    final displayY = tester.getTopLeft(find.text('display')).dy;
    final keypadY = tester.getTopLeft(find.text('keypad')).dy;
    final actionY = tester.getTopLeft(find.text('action')).dy;
    expect(displayY, lessThan(keypadY));
    expect(keypadY, lessThan(actionY));
  });

  testWidgets('wide: the real Itel tablet landscape size keeps action reachable, in the same '
      'pane as display, never below the keypad', (tester) async {
    // Same real dimensions used throughout the Tier 1/2 landscape
    // regression tests — see gas_numpad_sheet_test.dart.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final actionRect = tester.getRect(find.text('action'));
    expect(actionRect.bottom, lessThanOrEqualTo(screenHeight));

    // The defining property of the wide split: action sits in the same
    // (left) pane as display, both strictly left of the keypad's pane —
    // not below it, which is what the bug actually was.
    final displayX = tester.getTopLeft(find.text('display')).dx;
    final actionX = tester.getTopLeft(find.text('action')).dx;
    final keypadX = tester.getTopLeft(find.text('keypad')).dx;
    expect(actionX, lessThan(keypadX));
    expect(displayX, lessThan(keypadX));
  });

  testWidgets(
    'desktop: a real 1440x900 laptop window goes back to a single stacked column, not the '
    'tablet-landscape two-pane split — plenty of vertical height means the split isn\'t '
    'needed and just looks cramped in a popup',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // Stacked, not side-by-side — same ordering check as the narrow
      // case, the defining property that distinguishes it from the
      // tablet-landscape split (where action sits beside, not below,
      // the keypad).
      final displayY = tester.getTopLeft(find.text('display')).dy;
      final keypadY = tester.getTopLeft(find.text('keypad')).dy;
      final actionY = tester.getTopLeft(find.text('action')).dy;
      expect(displayY, lessThan(keypadY));
      expect(keypadY, lessThan(actionY));

      // "Sized up appropriately for the bigger screen" — wider than the
      // narrow phone column (440), not the tablet-landscape split's own
      // 900 cap (that cap governs the two-pane Row's overall width, not
      // a single stacked column).
      final box = tester.widget<ConstrainedBox>(
        find.byKey(const ValueKey('responsiveCenterConstraint')),
      );
      expect(box.constraints.maxWidth, 560);
    },
  );

  group('physical keyboard', () {
    testWidgets('is focused automatically on build, with no prior tap', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(FocusManager.instance.primaryFocus!.hasFocus, isTrue);
    });

    testWidgets('a digit key calls onKeyTap with that digit — same path as the on-screen key', (
      tester,
    ) async {
      final taps = <String>[];
      await tester.pumpWidget(harness(onKeyTap: taps.add));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad3);

      expect(taps, ['5', '3']);
    });

    testWidgets('Backspace and Delete both call onKeyTap(\'back\')', (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(harness(onKeyTap: taps.add));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);

      expect(taps, ['back', 'back']);
    });

    testWidgets('the period key calls onKeyTap(\'.\')', (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(harness(onKeyTap: taps.add));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.period);

      expect(taps, ['.']);
    });

    testWidgets('Enter triggers onSubmit when the primary action is enabled', (tester) async {
      var submitted = false;
      await tester.pumpWidget(harness(onSubmit: () => submitted = true));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(submitted, isTrue);
    });

    testWidgets(
      'Enter does nothing when onSubmit is null — mirroring a disabled primary action button',
      (tester) async {
        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();

        // No onSubmit provided; this must not throw.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
