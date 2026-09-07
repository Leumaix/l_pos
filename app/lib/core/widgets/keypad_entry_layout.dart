import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../responsive/breakpoints.dart';
import '../theme/app_spacing.dart';

/// Shared shape for every numeric-keypad-driven entry flow in the app —
/// Login (PIN), the gas numpad, product restock, and customer repayment
/// sheets: a display/context block, a numeric keypad, and one primary
/// action button.
///
/// Three responsive arrangements:
/// - Below [Breakpoints.wide]: stacks the three vertically exactly like
///   every one of these flows already did — wrapped in a scroll view as a
///   safety net, never as the primary layout mechanism.
/// - [Breakpoints.wide] up to (not including) [Breakpoints.desktop]: splits
///   into two columns (display+action on one side, the keypad on the
///   other) — the real fix for a bug on the shop's tablet in landscape,
///   where a short viewport pushed the action button below the fold (or,
///   before that fix, off-screen behind a hard RenderFlex overflow).
///   Unchanged by the desktop tier below — real hardware still needs
///   exactly this split.
/// - At/above [Breakpoints.desktop]: a real desktop browser window has
///   plenty of vertical height, so the two-column split isn't needed and
///   looks cramped in a popup — back to a single stacked column like the
///   narrow layout, just sized up (a wider cap, roomier gaps) for the
///   bigger screen.
///
/// Each side keeps its own scroll safety net regardless of width, so
/// neither branch can ever regress back into the original bug.
///
/// Also wires a physical keyboard to the exact same input path the
/// on-screen keys use: [onKeyTap] is called with '0'-'9', '.', or 'back'
/// for the matching physical key (main row or numpad digits, period, and
/// Backspace/Delete) — the identical callback passed to the on-screen
/// [keypad] itself (see each call site), so there is one source of truth
/// for input handling, not two parallel paths that can drift. Enter
/// triggers [onSubmit] when it's non-null, mirroring the primary action
/// button's own enabled condition. Autofocused on build so typing works
/// immediately, without first clicking into anything.
class KeypadEntryLayout extends StatelessWidget {
  final Widget display;
  final Widget keypad;
  final Widget action;
  final ValueChanged<String> onKeyTap;
  final VoidCallback? onSubmit;

  const KeypadEntryLayout({
    super.key,
    required this.display,
    required this.keypad,
    required this.action,
    required this.onKeyTap,
    this.onSubmit,
  });

  static final Map<LogicalKeyboardKey, String> _digitKeys = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final digit = _digitKeys[event.logicalKey];
    if (digit != null) {
      onKeyTap(digit);
      return KeyEventResult.handled;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      onKeyTap('back');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.period || key == LogicalKeyboardKey.numpadDecimal) {
      onKeyTap('.');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final onSubmit = this.onSubmit;
      if (onSubmit == null) return KeyEventResult.ignored;
      onSubmit();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (Breakpoints.isDesktop(context)) {
      content = ResponsiveCenter(
        maxWidth: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              display,
              const SizedBox(height: AppSpacing.xl),
              keypad,
              const SizedBox(height: AppSpacing.xl),
              action,
            ],
          ),
        ),
      );
    } else if (Breakpoints.isWide(context)) {
      content = ResponsiveCenter(
        maxWidth: 900,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    display,
                    const SizedBox(height: AppSpacing.xl),
                    action,
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: SingleChildScrollView(child: Center(child: keypad)),
            ),
          ],
        ),
      );
    } else {
      content = ResponsiveCenter(
        maxWidth: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              display,
              const SizedBox(height: AppSpacing.md),
              keypad,
              const SizedBox(height: AppSpacing.lg),
              action,
            ],
          ),
        ),
      );
    }

    return Focus(autofocus: true, onKeyEvent: _handleKeyEvent, child: content);
  }
}
