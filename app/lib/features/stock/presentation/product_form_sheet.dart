import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../sell/domain/product.dart';
import '../application/manage_catalog_controller.dart';

/// Add (existing == null) or edit (existing != null) a product. Editing
/// deliberately has no stock field at all — stock only ever moves
/// through Restock (or a sale), never a plain field edit, so there's
/// exactly one place that can change how much of something exists.
Future<void> showProductFormSheet(
  BuildContext context, {
  required String categoryId,
  Product? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.cardRadius)),
    ),
    builder: (context) => _ProductFormSheet(categoryId: categoryId, existing: existing),
  );
}

class _ProductFormSheet extends ConsumerStatefulWidget {
  final String categoryId;
  final Product? existing;

  const _ProductFormSheet({required this.categoryId, this.existing});

  @override
  ConsumerState<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends ConsumerState<_ProductFormSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late ProductUnit _unit;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _priceController = TextEditingController(text: existing != null ? existing.price.toString() : '');
    _stockController = TextEditingController();
    _unit = existing?.unit ?? ProductUnit.piece;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final price = int.tryParse(_priceController.text.trim());
    final stock = _isEdit ? 0 : int.tryParse(_stockController.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }
    if (!_isEdit && (stock == null || stock < 0)) {
      setState(() => _error = 'Enter a valid starting stock count.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final controller = ref.read(manageCatalogControllerProvider);
      if (_isEdit) {
        await controller.updateProduct(
          productId: widget.existing!.id,
          name: name,
          price: price,
          unit: _unit,
        );
      } else {
        await controller.createProduct(
          categoryId: widget.categoryId,
          name: name,
          price: price,
          stockCount: stock!,
          unit: _unit,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Could not save. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isEdit ? 'Edit product' : 'Add product', style: AppTextStyles.headingMd),
              const SizedBox(height: AppSpacing.lg),
              Text('Name', style: AppTextStyles.labelMd),
              const SizedBox(height: AppSpacing.xs),
              TextField(controller: _nameController, enabled: !_submitting),
              const SizedBox(height: AppSpacing.md),
              Text('Price (₦)', style: AppTextStyles.labelMd),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _priceController,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
              ),
              if (!_isEdit) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Starting stock count', style: AppTextStyles.labelMd),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _stockController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text('Unit', style: AppTextStyles.labelMd),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  _UnitChip(
                    label: 'Piece',
                    selected: _unit == ProductUnit.piece,
                    onTap: _submitting ? null : () => setState(() => _unit = ProductUnit.piece),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _UnitChip(
                    label: 'Yard',
                    selected: _unit == ProductUnit.yard,
                    onTap: _submitting ? null : () => setState(() => _unit = ProductUnit.yard),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 20,
                child: _error != null
                    ? Text(_error!, style: AppTextStyles.danger(AppTextStyles.bodySm))
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(label: 'Save', loading: _submitting, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _UnitChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentTintBg : AppColors.background,
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            border: Border.all(color: selected ? AppColors.accent : AppColors.border),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMd.copyWith(color: selected ? AppColors.accent : AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
