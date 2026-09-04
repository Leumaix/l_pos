import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/category_tabs.dart';
import '../application/cart_controller.dart';
import '../application/inventory_providers.dart';
import '../domain/cart.dart';
import '../domain/cart_line.dart';
import '../domain/category.dart';
import 'cart_line_tile.dart';
import 'cart_sheet.dart';
import 'gas_numpad_sheet.dart';
import 'product_tile.dart';

class SellScreen extends ConsumerStatefulWidget {
  final VoidCallback onGoToPayment;

  const SellScreen({super.key, required this.onGoToPayment});

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  String _selectedCategoryId = kGasCategoryId;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final categories = categoriesAsync.valueOrNull ?? const [];

    // A category the owner deleted while this screen was open (or one
    // that just hasn't loaded yet) falls back to Gas rather than showing
    // an empty/stale selection.
    final validIds = {kGasCategoryId, ...categories.map((c) => c.id)};
    final selected = validIds.contains(_selectedCategoryId)
        ? _selectedCategoryId
        : kGasCategoryId;

    final categoryItems = [
      const CategoryTabItem(id: kGasCategoryId, label: 'Gas'),
      for (final category in categories)
        CategoryTabItem(id: category.id, label: category.name),
    ];

    final isWide = Breakpoints.isWide(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Sell', style: AppTextStyles.headingSm),
      ),
      body: SafeArea(
        top: false,
        // Wide (tablet, e.g. landscape counter-mount): a persistent rail
        // (running cart + total + Go to payment only) beside category
        // tabs above the product grid — matches the reference POS
        // layout, replacing the floating cart bar/bottom sheet for this
        // mode only. Narrow (phone): today's stacked tabs-above-grid
        // layout, completely unchanged, still using the floating
        // _CartBar + showCartSheet.
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 320,
                    child: _SellCartRail(
                      cart: cart,
                      controller: ref.read(cartControllerProvider.notifier),
                      onGoToPayment: widget.onGoToPayment,
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            0,
                          ),
                          child: CategoryTabs(
                            items: categoryItems,
                            selectedId: selected,
                            onSelected: (id) =>
                                setState(() => _selectedCategoryId = id),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: _CategoryBody(categoryId: selected),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: ResponsiveCenter(
                      maxWidth: 700,
                      child: CategoryTabs(
                        items: categoryItems,
                        selectedId: selected,
                        onSelected: (id) =>
                            setState(() => _selectedCategoryId = id),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.xxl + AppSpacing.tabBarHeight,
                      ),
                      child: ResponsiveCenter(
                        maxWidth: 700,
                        child: _CategoryBody(categoryId: selected),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: (!isWide && !cart.isEmpty)
          ? _CartBar(
              itemCount: cart.lines.length,
              total: cart.total,
              onTap: () =>
                  showCartSheet(context, onGoToPayment: widget.onGoToPayment),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _SellCartRail extends StatelessWidget {
  final Cart cart;
  final CartController controller;
  final VoidCallback onGoToPayment;

  const _SellCartRail({
    required this.cart,
    required this.controller,
    required this.onGoToPayment,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cart', style: AppTextStyles.headingSm),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Text(
                      'Cart is empty',
                      style: AppTextStyles.muted(AppTextStyles.bodyMd),
                    ),
                  )
                : ListView.separated(
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => const Divider(
                      color: AppColors.border,
                      height: AppSpacing.lg,
                    ),
                    itemBuilder: (context, index) {
                      final line = cart.lines[index];
                      final productLine = line is ProductCartLine ? line : null;
                      // Same proactive-disable reasoning as the narrow
                      // cart sheet — see cart_sheet.dart.
                      final atStockLimit =
                          productLine != null &&
                          productLine.quantity >=
                              productLine.product.stockCount;

                      return CartLineTile(
                        line: line,
                        onRemove: () => controller.removeCartLine(line.id),
                        onIncrement: productLine != null && !atStockLimit
                            ? () =>
                                  controller.addCartProduct(productLine.product)
                            : null,
                        onDecrement: productLine != null
                            ? () => controller.decrementCartProduct(line.id)
                            : null,
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: AppColors.border),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: AppTextStyles.labelLg),
              Text(formatNaira(cart.total), style: AppTextStyles.numericLg),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Go to payment',
            onPressed: cart.isEmpty ? null : onGoToPayment,
          ),
        ],
      ),
    );
  }
}

class _CategoryBody extends ConsumerWidget {
  final String categoryId;

  const _CategoryBody({required this.categoryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (categoryId == kGasCategoryId) {
      final rate = ref.watch(gasRateProvider);
      return _GasTile(rate: rate.nairaPerKg.round());
    }

    final productsAsync = ref.watch(productsProvider);

    return productsAsync.when(
      data: (products) {
        final filtered = products
            .where((p) => p.categoryId == categoryId)
            .toList();
        final controller = ref.read(cartControllerProvider.notifier);

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
          // Sized by available width, not a wide/narrow breakpoint flag:
          // the wide-mode rail leaves a narrower main pane than a
          // full-width narrow layout ever did, and a fixed column count
          // tuned for one doesn't fit the other — ProductTile's content
          // genuinely needs at least ~160 logical px of width at this
          // aspect ratio, or its own Column overflows.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.95,
          ),
          itemBuilder: (context, index) {
            final product = filtered[index];
            return ProductTile(
              product: product,
              onTap: () {
                final result = controller.addCartProduct(product);
                if (result.blocked && result.message != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.message!),
                      backgroundColor: AppColors.dangerBg,
                    ),
                  );
                }
              },
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

class _GasTile extends StatelessWidget {
  final int rate;

  const _GasTile({required this.rate});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        onTap: () => showGasNumpadSheet(context),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  gradient: AppColors.accentGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_fire_department,
                  color: AppColors.onAccent,
                  size: 28,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Cooking Gas', style: AppTextStyles.headingSm),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatNaira(rate)}/kg',
                style: AppTextStyles.secondary(AppTextStyles.bodyMd),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Tap to sell by kg or by amount',
                style: AppTextStyles.muted(AppTextStyles.bodySm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  final int itemCount;
  final int total;
  final VoidCallback onTap;

  const _CartBar({
    required this.itemCount,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: Container(
          height: AppSpacing.minTouchTarget + 8,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          constraints: const BoxConstraints(minWidth: 260),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shopping_cart, color: AppColors.onAccent, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$itemCount item${itemCount == 1 ? '' : 's'}',
                style: AppTextStyles.buttonLabel.copyWith(
                  color: AppColors.onAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Container(
                width: 1,
                height: 18,
                color: AppColors.onAccent.withValues(alpha: 0.3),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                formatNaira(total),
                style: AppTextStyles.buttonLabel.copyWith(
                  color: AppColors.onAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
