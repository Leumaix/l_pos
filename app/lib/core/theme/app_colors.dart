import 'package:flutter/material.dart';

/// The Leumadepos design system's fixed dark, high-contrast, amber-accent
/// palette. There is no light theme — this app is designed dark-only.
abstract final class AppColors {
  static const background = Color(0xFF0B0D10);
  static const surface = Color(0xFF16191E);
  static const border = Color(0xFF262B33);

  static const textPrimary = Color(0xFFF5F6F7);
  static const textSecondary = Color(0xFF9AA1AC);
  static const textMuted = Color(0xFF6B7280);
  static const textFaint = Color(0xFF4B5563);

  static const accent = Color(0xFFF5A524);
  static const accentGradientEnd = Color(0xFFD6820E);
  static const accentTintBg = Color(0xFF1C1508);

  static const success = Color(0xFF4ADE80);
  static const successBg = Color(0xFF12201A);
  static const danger = Color(0xFFF0665C);
  static const dangerBg = Color(0xFF241214);

  /// Text color on an enabled amber button.
  static const onAccent = Color(0xFF1A1300);
  static const buttonDisabledBg = Color(0xFF1C1F25);
  static const buttonDisabledText = Color(0xFF5B6270);

  static const tabBarBackground = Color(0xFF0E1115);
  static const tabBarBorder = Color(0xFF1B1F26);
  static const tabInactive = Color(0xFF6B7280);

  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentGradientEnd],
  );
}
