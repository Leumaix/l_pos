import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Full-width primary button: amber background + dark text when enabled,
/// dark background + muted text when [onPressed] is null.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final bool loading;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
    this.loading = false,
  });

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.minTouchTarget + 8,
      child: Material(
        color: _enabled ? AppColors.accent : AppColors.buttonDisabledBg,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: InkWell(
          onTap: _enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          child: Center(
            child: loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.onAccent,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.sm)],
                      Text(
                        label,
                        style: AppTextStyles.buttonLabel.copyWith(
                          color: _enabled ? AppColors.onAccent : AppColors.buttonDisabledText,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
