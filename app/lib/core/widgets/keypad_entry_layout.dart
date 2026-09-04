import 'package:flutter/material.dart';

import '../responsive/breakpoints.dart';
import '../theme/app_spacing.dart';

/// Shared shape for every numeric-keypad-driven entry flow in the app —
/// Login (PIN), the gas numpad, product restock, and customer repayment
/// sheets: a display/context block, a numeric keypad, and one primary
/// action button.
///
/// Below [Breakpoints.wide], stacks the three vertically exactly like
/// every one of these flows already did — wrapped in a scroll view as a
/// safety net, never as the primary layout mechanism. At/above it, splits
/// into two columns (display+action on one side, the keypad on the
/// other) so the action button is never pushed below the keypad on a
/// short, landscape-shaped viewport — the real fix for a bug where
/// reaching it required scrolling mid-entry, or (before that) a hard
/// RenderFlex overflow made it unreachable outright. Each side keeps its
/// own scroll safety net regardless of width, so neither branch can ever
/// regress back into that.
class KeypadEntryLayout extends StatelessWidget {
  final Widget display;
  final Widget keypad;
  final Widget action;

  const KeypadEntryLayout({
    super.key,
    required this.display,
    required this.keypad,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    if (Breakpoints.isWide(context)) {
      return ResponsiveCenter(
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
    }

    return ResponsiveCenter(
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
}
