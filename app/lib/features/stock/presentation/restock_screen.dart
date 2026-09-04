import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gas_stock/gas_stock.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/category_tabs.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../../sell/application/inventory_providers.dart';
import '../../sell/domain/category.dart';
import '../../sell/domain/product.dart';
import '../application/restock_controller.dart';
import 'product_restock_sheet.dart';

class RestockScreen extends ConsumerStatefulWidget {
  const RestockScreen({super.key});

  @override
  ConsumerState<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends ConsumerState<RestockScreen> {
  String _selectedCategoryId = kGasCategoryId;

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final categories = categoriesAsync.valueOrNull ?? const [];
    final validIds = {kGasCategoryId, ...categories.map((c) => c.id)};
    final selected = validIds.contains(_selectedCategoryId)
        ? _selectedCategoryId
        : kGasCategoryId;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Restock', style: AppTextStyles.headingSm),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: ResponsiveCenter(
            maxWidth: 480,
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
                  const _GasRestockBody()
                else
                  _ProductRestockGrid(categoryId: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GasRestockBody extends ConsumerStatefulWidget {
  const _GasRestockBody();

  @override
  ConsumerState<_GasRestockBody> createState() => _GasRestockBodyState();
}

class _GasRestockBodyState extends ConsumerState<_GasRestockBody> {
  String _input = '';
  bool _submitting = false;

  num? get _kg => _input.isEmpty ? null : num.tryParse(_input);

  void _tapKey(String key) {
    setState(() {
      if (key == 'back') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
        return;
      }
      if (key == '.' && _input.contains('.')) return;
      if (_input.length >= 8) return;
      _input += key;
    });
  }

  Future<void> _confirm() async {
    final kg = _kg;
    if (kg == null || kg <= 0 || _submitting) return;

    setState(() => _submitting = true);
    try {
      await ref.read(restockControllerProvider).commitRestock(kg);
      if (mounted) {
        setState(() {
          _input = '';
          _submitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${formatKg(kg.toDouble())} to gas stock'),
            backgroundColor: AppColors.successBg,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not record restock. Try again.'),
            backgroundColor: AppColors.dangerBg,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate = ref.watch(gasRateProvider);
    final gasStockAsync = ref.watch(gasStockProvider);
    final kg = _kg;

    return gasStockAsync.when(
      data: (gasStock) {
        final currentKg = kgRemaining(gasStock, rate);
        final preview = (kg != null && kg > 0)
            ? restock(gasStock, kg, rate)
            : null;
        final newTotalKg = preview != null
            ? kgRemaining(preview.stock, rate)
            : currentKg;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Current stock',
                    style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                  ),
                  Text(formatKg(currentKg), style: AppTextStyles.numericMd),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: Column(
                children: [
                  Text(
                    'kg delivered',
                    style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _input.isEmpty ? '0 kg' : '$_input kg',
                    style: AppTextStyles.numericXl,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (preview != null)
              AppCard(
                color: AppColors.successBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${kg.toString()} kg × ${formatNaira(rate.nairaPerKg.round())}/kg',
                            style: AppTextStyles.secondary(
                              AppTextStyles.bodySm,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '+${formatNaira(preview.unitsAdded)}',
                          style: AppTextStyles.success(AppTextStyles.numericSm),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('New total', style: AppTextStyles.labelMd),
                        Text(
                          formatKg(newTotalKg),
                          style: AppTextStyles.success(AppTextStyles.numericMd),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  'This adds to the existing stock — it never replaces it.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.muted(AppTextStyles.bodySm),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            NumericKeypad(onKeyTap: _tapKey, showDecimal: true),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Confirm restock',
              loading: _submitting,
              onPressed: (kg != null && kg > 0 && !_submitting)
                  ? _confirm
                  : null,
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xxl),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      ),
      error: (err, _) => Text(
        'Could not load gas stock',
        style: AppTextStyles.danger(AppTextStyles.bodyMd),
      ),
    );
  }
}

class _ProductRestockGrid extends ConsumerWidget {
  final String categoryId;

  const _ProductRestockGrid({required this.categoryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);

    return productsAsync.when(
      data: (products) {
        final filtered = products
            .where((p) => p.categoryId == categoryId)
            .toList();
        final columns = Breakpoints.isWide(context) ? 3 : 2;

        if (filtered.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xxl),
            child: Center(child: Text('No products in this category yet')),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filtered.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.95,
          ),
          itemBuilder: (context, index) {
            final product = filtered[index];
            return _RestockProductTile(
              product: product,
              onTap: () => showProductRestockSheet(context, product),
            );
          },
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xxl),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxl),
        child: Text(
          'Could not load products',
          style: AppTextStyles.danger(AppTextStyles.bodyMd),
        ),
      ),
    );
  }
}

/// Deliberately its own tile, not ProductTile: ProductTile disables its
/// tap when a product is out of stock (correct for Sell — you can't sell
/// what isn't there) but that's exactly the product restocking most
/// needs to reach here, so it must always stay tappable.
class _RestockProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _RestockProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stockCount <= 0;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
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
              Text(
                outOfStock ? 'Out of stock' : '${product.stockCount} in stock',
                style: AppTextStyles.bodySm.copyWith(
                  color: outOfStock ? AppColors.danger : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
