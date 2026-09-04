import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Stand-in for a tab not built yet, so the bottom-nav shell is fully
/// clickable end to end while each screen gets built in turn.
class PlaceholderScreen extends StatelessWidget {
  final String title;

  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          '$title — coming soon',
          style: AppTextStyles.muted(AppTextStyles.bodyLg).copyWith(color: AppColors.textMuted),
        ),
      ),
    );
  }
}
