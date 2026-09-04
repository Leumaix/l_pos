import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Named text styles per the design system: Space Grotesk for headings and
/// all numeric values (tabular figures, so digits align in columns —
/// totals, PIN dots, receipt lines), Work Sans for body copy and labels.
abstract final class AppTextStyles {
  static TextStyle _grotesk({
    required double size,
    required FontWeight weight,
    Color color = AppColors.textPrimary,
    List<FontFeature>? features,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight,
      color: color,
      fontFeatures: features ?? const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle _work({
    required double size,
    required FontWeight weight,
    Color color = AppColors.textPrimary,
  }) {
    return GoogleFonts.workSans(fontSize: size, fontWeight: weight, color: color);
  }

  // Headings (Space Grotesk)
  static TextStyle headingLg = _grotesk(size: 28, weight: FontWeight.w700);
  static TextStyle headingMd = _grotesk(size: 22, weight: FontWeight.w600);
  static TextStyle headingSm = _grotesk(size: 18, weight: FontWeight.w600);

  // Numeric display values (Space Grotesk, tabular figures)
  static TextStyle numericXl = _grotesk(size: 36, weight: FontWeight.w700);
  static TextStyle numericLg = _grotesk(size: 28, weight: FontWeight.w700);
  static TextStyle numericMd = _grotesk(size: 20, weight: FontWeight.w600);
  static TextStyle numericSm = _grotesk(size: 16, weight: FontWeight.w600);

  // Body / labels (Work Sans)
  static TextStyle bodyLg = _work(size: 16, weight: FontWeight.w400);
  static TextStyle bodyMd = _work(size: 14, weight: FontWeight.w400);
  static TextStyle bodySm = _work(size: 12, weight: FontWeight.w400);

  static TextStyle labelLg = _work(size: 16, weight: FontWeight.w600);
  static TextStyle labelMd = _work(size: 14, weight: FontWeight.w600);
  static TextStyle labelSm = _work(size: 12, weight: FontWeight.w600);

  static TextStyle buttonLabel = _work(size: 16, weight: FontWeight.w700);

  static TextStyle secondary(TextStyle base) => base.copyWith(color: AppColors.textSecondary);
  static TextStyle muted(TextStyle base) => base.copyWith(color: AppColors.textMuted);
  static TextStyle faint(TextStyle base) => base.copyWith(color: AppColors.textFaint);
  static TextStyle accent(TextStyle base) => base.copyWith(color: AppColors.accent);
  static TextStyle success(TextStyle base) => base.copyWith(color: AppColors.success);
  static TextStyle danger(TextStyle base) => base.copyWith(color: AppColors.danger);
}
