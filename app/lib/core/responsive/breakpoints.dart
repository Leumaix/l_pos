import 'package:flutter/widgets.dart';

/// Three-tier responsive layout: narrow (phone), wide (tablet, e.g. the
/// shop's Galaxy Tab A9+ at 1200x1920), and desktop (a real laptop/desktop
/// browser window on the web/PWA build). Based on logical/density-independent
/// pixels via MediaQuery, never a fixed frame size.
abstract final class Breakpoints {
  /// Below this width is "phone": single-column layout as designed.
  /// At or above it is "tablet": content gets constrained/centered or
  /// grids gain columns, per-screen — see [ResponsiveCenter].
  static const wide = 600.0;

  /// At or above this width is "desktop" — comfortably above the tablet
  /// reference size used throughout the existing wide-mode tests (a real
  /// 1280x800 physical tablet at 1.5x DPR ≈ 853 logical px), so raising
  /// this threshold can never change tablet behavior. Tablet-designed
  /// layouts (e.g. Sell's rail + grid) are left alone at this width;
  /// [ResponsiveCenter]'s [ResponsiveCenter.desktopMaxWidth] and
  /// [AppSideRail] are what actually respond to it.
  static const desktop = 1024.0;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;
}

/// Wraps phone-designed content so it doesn't stretch edge-to-edge on a
/// tablet: constrains to [maxWidth] and centers, while staying full-width
/// below the wide breakpoint. Use for anything not explicitly redesigned
/// for tablet (numpads, forms, single-column cards).
///
/// [desktopMaxWidth], when given, widens that cap further at/above
/// [Breakpoints.desktop] — a real desktop browser window is wide enough
/// that the tablet-tuned [maxWidth] alone still leaves excessive dead
/// margin on either side. Omitting it changes nothing at any width, so
/// every pre-existing call site (forms, receipt, keypad layouts) is
/// unaffected.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double? desktopMaxWidth;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 520,
    this.desktopMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final desktopMaxWidth = this.desktopMaxWidth;
    final effectiveMaxWidth =
        (desktopMaxWidth != null && Breakpoints.isDesktop(context))
        ? desktopMaxWidth
        : maxWidth;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        key: const ValueKey('responsiveCenterConstraint'),
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
        child: child,
      ),
    );
  }
}
