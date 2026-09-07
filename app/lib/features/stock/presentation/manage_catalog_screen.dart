import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../sell/application/inventory_providers.dart';
import '../../sell/data/inventory_repository.dart';
import '../../sell/domain/category.dart';
import '../../sell/domain/product.dart';
import '../application/manage_catalog_controller.dart';

/// Owner-only. Gas isn't here at all — it has no owner-editable name,
/// price, or stock, and keeps its own hardcoded behavior everywhere; see
/// InventoryRepository's doc comment. This screen manages everything
/// else: categories, and the products within them.
class ManageCatalogScreen extends ConsumerStatefulWidget {
  const ManageCatalogScreen({super.key});

  @override
  ConsumerState<ManageCatalogScreen> createState() => _ManageCatalogScreenState();
}

class _ManageCatalogScreenState extends ConsumerState<ManageCatalogScreen> {
  final _newCategoryController = TextEditingController();

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  Future<void> _addCategory() async {
    final name = _newCategoryController.text.trim();
    if (name.isEmpty) return;
    await ref.read(manageCatalogControllerProvider).createCategory(name);
    _newCategoryController.clear();
    setState(() {});
  }

  Future<void> _rename(Category category) async {
    // The dialog owns its own TextEditingController (see
    // _RenameCategoryDialog) rather than one created and disposed here —
    // disposing it right after showDialog() returns races the dialog's
    // own closing animation, which can still rebuild the TextField (and
    // touch the now-disposed controller) for a few more frames.
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _RenameCategoryDialog(initialName: category.name),
    );
    if (newName == null || newName.isEmpty || newName == category.name) return;
    await ref.read(manageCatalogControllerProvider).renameCategory(category.id, newName);
  }

  Future<void> _delete(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${category.name}"?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: AppTextStyles.danger(AppTextStyles.bodyMd)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(manageCatalogControllerProvider).deleteCategory(category.id);
    } on CategoryNotEmptyException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Move or delete the ${e.productCount} product${e.productCount == 1 ? '' : 's'} '
            'in "${category.name}" first.',
          ),
          backgroundColor: AppColors.dangerBg,
        ),
      );
    }
  }

  Future<void> _move(List<Category> sorted, int index, int delta) async {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= sorted.length) return;
    final reordered = sorted.map((c) => c.id).toList();
    final moved = reordered.removeAt(index);
    reordered.insert(newIndex, moved);
    await ref.read(manageCatalogControllerProvider).reorderCategories(reordered);
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Catalog'), backgroundColor: AppColors.background),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 640,
            desktopMaxWidth: 960,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newCategoryController,
                          decoration: const InputDecoration(hintText: 'New category name'),
                          onSubmitted: (_) => _addCategory(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(width: 90, child: AppButton(label: 'Add', onPressed: _addCategory)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                categoriesAsync.when(
                  data: (categories) {
                    final sorted = [...categories]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                    if (sorted.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Text(
                          'No categories yet — add one above to start building the catalog.',
                          style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                        ),
                      );
                    }
                    final counts = <String, int>{};
                    for (final product in productsAsync.valueOrNull ?? const <Product>[]) {
                      counts[product.categoryId] = (counts[product.categoryId] ?? 0) + 1;
                    }
                    return Column(
                      children: [
                        for (var i = 0; i < sorted.length; i++)
                          _CategoryRow(
                            category: sorted[i],
                            productCount: counts[sorted[i].id] ?? 0,
                            canMoveUp: i > 0,
                            canMoveDown: i < sorted.length - 1,
                            onMoveUp: () => _move(sorted, i, -1),
                            onMoveDown: () => _move(sorted, i, 1),
                            onRename: () => _rename(sorted[i]),
                            onDelete: () => _delete(sorted[i]),
                            onOpen: () => context.push('/manage-catalog/${sorted[i].id}', extra: sorted[i].name),
                          ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                  ),
                  error: (err, _) => Text(
                    'Could not load categories',
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

class _RenameCategoryDialog extends StatefulWidget {
  final String initialName;

  const _RenameCategoryDialog({required this.initialName});

  @override
  State<_RenameCategoryDialog> createState() => _RenameCategoryDialogState();
}

class _RenameCategoryDialogState extends State<_RenameCategoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename category'),
      content: TextField(controller: _controller, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final Category category;
  final int productCount;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  const _CategoryRow({
    required this.category,
    required this.productCount,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRename,
    required this.onDelete,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_drop_up),
                  onPressed: canMoveUp ? onMoveUp : null,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_drop_down),
                  onPressed: canMoveDown ? onMoveDown : null,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Expanded(
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(category.name, style: AppTextStyles.labelLg),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '$productCount product${productCount == 1 ? '' : 's'} — tap to add or edit',
                              style: AppTextStyles.secondary(AppTextStyles.bodySm),
                            ),
                          ],
                        ),
                      ),
                      // The row's own tap target was previously invisible
                      // — nothing distinguished it from the surrounding
                      // reorder/rename/delete icons, so a first-time
                      // owner had no obvious way to discover it opens
                      // this category's products (and its "Add product"
                      // button). This chevron plus the hint text above
                      // make that discoverable.
                      const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onRename),
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
