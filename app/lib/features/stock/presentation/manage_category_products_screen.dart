import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../sell/application/inventory_providers.dart';
import '../../sell/domain/product.dart';
import '../application/manage_catalog_controller.dart';
import 'product_form_sheet.dart';

/// Owner-only: add/edit/delete the products within one category. Reached
/// by tapping a category on ManageCatalogScreen.
class ManageCategoryProductsScreen extends ConsumerWidget {
  final String categoryId;
  final String? categoryName;

  const ManageCategoryProductsScreen({super.key, required this.categoryId, this.categoryName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    final controller = ref.read(manageCatalogControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName ?? 'Category'),
        backgroundColor: AppColors.background,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 640,
            desktopMaxWidth: 960,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppButton(
                  label: 'Add product',
                  onPressed: () => showProductFormSheet(context, categoryId: categoryId),
                ),
                const SizedBox(height: AppSpacing.xl),
                productsAsync.when(
                  data: (products) {
                    final filtered = products.where((p) => p.categoryId == categoryId).toList();
                    if (filtered.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Text(
                          'No products in this category yet.',
                          style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final product in filtered)
                          _ProductRow(
                            product: product,
                            onEdit: () => showProductFormSheet(
                              context,
                              categoryId: categoryId,
                              existing: product,
                            ),
                            onDelete: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: Text('Delete "${product.name}"?'),
                                  content: const Text('This can\'t be undone.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(dialogContext).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.of(dialogContext).pop(true),
                                      child: Text(
                                        'Delete',
                                        style: AppTextStyles.danger(AppTextStyles.bodyMd),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await controller.deleteProduct(product.id);
                              }
                            },
                          ),
                      ],
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductRow({required this.product, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final unitSuffix = product.unit == ProductUnit.yard ? '/yard' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: AppTextStyles.labelLg),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${formatNaira(product.price)}$unitSuffix · ${product.stockCount} in stock',
                    style: AppTextStyles.secondary(AppTextStyles.bodySm),
                  ),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
