import 'package:flutter/material.dart';

import '../../../core/constants/stock_thresholds.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../domain/product.dart';

class ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductTile({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stockCount <= 0;
    final lowStock = !outOfStock && product.stockCount <= kLowStockThreshold;
    final unitSuffix = product.unit == ProductUnit.yard ? '/yard' : '';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        onTap: outOfStock ? null : onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Opacity(
          opacity: outOfStock ? 0.5 : 1,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  product.name,
                  style: AppTextStyles.labelMd,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('${formatNaira(product.price)}$unitSuffix', style: AppTextStyles.numericSm),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  outOfStock ? 'Out of stock' : '${product.stockCount} in stock',
                  style: AppTextStyles.bodySm.copyWith(
                    color: outOfStock
                        ? AppColors.danger
                        : (lowStock ? AppColors.danger : AppColors.textMuted),
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
