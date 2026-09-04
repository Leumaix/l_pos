import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

class CategoryTabItem {
  final String id;
  final String label;

  const CategoryTabItem({required this.id, required this.label});
}

/// The Gas-pinned-first, then-owner's-categories picker shared by Sell,
/// Stock, and Restock. Horizontally scrollable rather than
/// equal-width-Expanded chips — the category list is owner-managed and
/// unbounded now, unlike the old fixed 3-value picker this replaced.
class CategoryTabs extends StatelessWidget {
  final List<CategoryTabItem> items;
  final String selectedId;
  final ValueChanged<String> onSelected;

  const CategoryTabs({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in items) ...[
            _CategoryChip(
              label: item.label,
              selected: item.id == selectedId,
              onTap: () => onSelected(item.id),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentTintBg : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        child: Container(
          height: AppSpacing.minTouchTarget,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            border: Border.all(color: selected ? AppColors.accent : AppColors.border),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMd.copyWith(
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
