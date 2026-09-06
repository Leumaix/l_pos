import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'app_bottom_nav.dart';

/// The desktop-width companion to [AppBottomNav] — same tabs (reuses its
/// [NavTabItem] list rather than a parallel one), same by-label
/// [ValueKey] stability for the same reason (see [AppBottomNav]'s own
/// doc comment), laid out as a vertical rail down the left edge instead
/// of a horizontal bar along the bottom. Swapped in by AppShell at
/// [Breakpoints.isDesktop] widths; below that, [AppBottomNav] is
/// unchanged.
class AppSideRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NavTabItem> items;

  const AppSideRail({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.railWidth,
      decoration: const BoxDecoration(
        color: AppColors.tabBarBackground,
        border: Border(right: BorderSide(color: AppColors.tabBarBorder)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),
            for (var i = 0; i < items.length; i++)
              Padding(
                key: ValueKey(items[i].label),
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _RailTab(
                  item: items[i],
                  active: i == currentIndex,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailTab extends StatelessWidget {
  final NavTabItem item;
  final bool active;
  final VoidCallback onTap;

  const _RailTab({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.tabInactive;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? item.activeIcon : item.icon,
                color: color,
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: AppTextStyles.labelSm.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
