import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A row of PIN entry indicators: a filled amber dot for each digit
/// entered, a dash placeholder for each still empty.
class PinDots extends StatelessWidget {
  final int length;
  final int filled;

  const PinDots({super.key, this.length = 4, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: isFilled
              ? Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                )
              : Container(
                  width: 16,
                  height: 2,
                  color: AppColors.textFaint,
                ),
        );
      }),
    );
  }
}
