import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/core/widgets/keypad_entry_layout.dart';

void main() {
  Widget harness() => const MaterialApp(
    home: Scaffold(
      body: KeypadEntryLayout(
        display: Text('display'),
        keypad: SizedBox(height: 300, width: 300, child: Text('keypad')),
        action: Text('action'),
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
}
