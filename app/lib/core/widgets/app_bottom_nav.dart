import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

class NavTabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const NavTabItem({required this.icon, required this.activeIcon, required this.label});
}

/// The 5-tab bottom navigation bar: Home, Sell, Customers, Stock, Reports.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NavTabItem> items;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.tabBarHeight,
      decoration: const BoxDecoration(
        color: AppColors.tabBarBackground,
        border: Border(top: BorderSide(color: AppColors.tabBarBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                // Keyed by label (stable, unique per tab) — this list's
                // length can change (an attendant sees fewer tabs than
                // an owner), and an unkeyed list risks Flutter
                // reconciling a rebuilt item against the wrong previous
                // element, leaving a stale gesture recognizer attached
                // to the wrong tab. See app_shell.dart's isOwner select
                // for the other half of this fix.
                key: ValueKey(items[i].label),
                child: _NavTab(
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

class _NavTab extends StatelessWidget {
  final NavTabItem item;
  final bool active;
  final VoidCallback onTap;

  const _NavTab({required this.item, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.tabInactive;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? item.activeIcon : item.icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(item.label, style: AppTextStyles.labelSm.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
