import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gas_stock/gas_stock.dart';

import '../../../core/constants/stock_thresholds.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/category_tabs.dart';
import '../../business/application/business_providers.dart';
import '../../sell/application/inventory_providers.dart';
import '../../sell/domain/category.dart';
import '../../sell/domain/product.dart';

class StockScreen extends ConsumerStatefulWidget {
  final VoidCallback onRestock;

  const StockScreen({super.key, required this.onRestock});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  String _selectedCategoryId = kGasCategoryId;

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final categories = categoriesAsync.valueOrNull ?? const [];
    final validIds = {kGasCategoryId, ...categories.map((c) => c.id)};
    final selected = validIds.contains(_selectedCategoryId) ? _selectedCategoryId : kGasCategoryId;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Stock', style: AppTextStyles.headingSm),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 640,
            desktopMaxWidth: 960,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CategoryTabs(
                  items: [
                    const CategoryTabItem(id: kGasCategoryId, label: 'Gas'),
                    for (final category in categories)
                      CategoryTabItem(id: category.id, label: category.name),
                  ],
                  selectedId: selected,
                  onSelected: (id) => setState(() => _selectedCategoryId = id),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (selected == kGasCategoryId)
                  _GasSection(onRestock: widget.onRestock)
                else
                  _ProductCategorySection(categoryId: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GasSection extends ConsumerWidget {
  final VoidCallback onRestock;

  const _GasSection({required this.onRestock});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gasStockAsync = ref.watch(gasStockProvider);
    final rate = ref.watch(gasRateProvider);
    final capacityKg = ref.watch(gasTankCapacityKgProvider);

    return gasStockAsync.when(
      data: (gasStock) => _GasGaugeCard(
        gasStock: gasStock,
        rate: rate,
        capacityKg: capacityKg,
        onRestock: onRestock,
      ),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      ),
      error: (err, _) => Text(
        'Could not load gas stock',
        style: AppTextStyles.danger(AppTextStyles.bodyMd),
      ),
    );
  }
}

class _ProductCategorySection extends ConsumerWidget {
  final String categoryId;

  const _ProductCategorySection({required this.categoryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);

    return productsAsync.when(
      data: (products) {
        final filtered = products.where((p) => p.categoryId == categoryId).toList();

        if (filtered.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xxl),
            child: Center(child: Text('No products in this category yet')),
          );
        }

        return AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (var i = 0; i < filtered.length; i++)
                _StockRow(product: filtered[i], isLast: i == filtered.length - 1),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      ),
      error: (err, _) => Text(
        'Could not load products',
        style: AppTextStyles.danger(AppTextStyles.bodyMd),
      ),
    );
  }
}

class _GasGaugeCard extends StatelessWidget {
  final GasStock gasStock;
  final GasRate rate;
  final double capacityKg;
  final VoidCallback onRestock;

  const _GasGaugeCard({
    required this.gasStock,
    required this.rate,
    required this.capacityKg,
    required this.onRestock,
  });

  @override
  Widget build(BuildContext context) {
    // The one source of truth for kg-remaining, shared with Home's stat
    // card — never recomputed independently here, so the two figures
    // can't drift apart if the rate ever changes.
    final kg = kgRemaining(gasStock, rate);
    final fraction = (kg / capacityKg).clamp(0.0, 1.0);
    final isNegative = kg < 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Gas remaining', style: AppTextStyles.secondary(AppTextStyles.bodyMd)),
              TextButton(onPressed: onRestock, child: const Text('Restock')),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatKg(kg),
            style: AppTextStyles.numericXl.copyWith(
              color: isNegative ? AppColors.danger : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: AppColors.background,
              valueColor: AlwaysStoppedAnimation(
                isNegative ? AppColors.danger : AppColors.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isNegative
                ? 'Stock is negative — needs reconciliation'
                : '${(fraction * 100).round()}% of ${capacityKg.round()}kg capacity',
            style: (isNegative ? AppTextStyles.danger : AppTextStyles.muted)(AppTextStyles.bodySm),
          ),
        ],
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  final Product product;
  final bool isLast;

  const _StockRow({required this.product, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stockCount <= 0;
    final lowStock = !outOfStock && product.stockCount <= kLowStockThreshold;
    final flagged = outOfStock || lowStock;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(product.name, style: AppTextStyles.bodyLg),
          Row(
            children: [
              if (flagged) ...[
                const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.danger),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                outOfStock ? 'Out of stock' : '${product.stockCount}',
                style: AppTextStyles.numericSm.copyWith(
                  color: flagged ? AppColors.danger : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
