import 'package:flutter/widgets.dart';

/// Two-tier responsive layout: narrow (phone) vs wide (tablet, e.g. the
/// shop's Galaxy Tab A9+ at 1200x1920). Based on logical/density-independent
/// pixels via MediaQuery, never a fixed frame size.
abstract final class Breakpoints {
  /// Below this width is "phone": single-column layout as designed.
  /// At or above it is "tablet": content gets constrained/centered or
  /// grids gain columns, per-screen — see [ResponsiveCenter].
  static const wide = 600.0;

  static bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wide;
}

/// Wraps phone-designed content so it doesn't stretch edge-to-edge on a
/// tablet: constrains to [maxWidth] and centers, while staying full-width
/// below the wide breakpoint. Use for anything not explicitly redesigned
/// for tablet (numpads, forms, single-column cards).
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveCenter({super.key, required this.child, this.maxWidth = 520});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
