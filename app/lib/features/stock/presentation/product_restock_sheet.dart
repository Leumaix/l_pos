import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/keypad_entry_layout.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../../sell/domain/product.dart';
import '../application/restock_controller.dart';

/// A cylinder/accessory delivery: how many more of [product] just came
/// in. Adds on top of the existing stockCount — same
/// additive-never-overwrite contract proven for gas restocking (see
/// RestockController.commitProductRestock).
Future<void> showProductRestockSheet(BuildContext context, Product product) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.cardRadius),
      ),
    ),
    builder: (context) => _ProductRestockSheet(product: product),
  );
}

class _ProductRestockSheet extends ConsumerStatefulWidget {
  final Product product;

  const _ProductRestockSheet({required this.product});

  @override
  ConsumerState<_ProductRestockSheet> createState() =>
      _ProductRestockSheetState();
}

class _ProductRestockSheetState extends ConsumerState<_ProductRestockSheet> {
  String _input = '';
  bool _submitting = false;

  int? get _quantity => _input.isEmpty ? null : int.tryParse(_input);

  void _tapKey(String key) {
    setState(() {
      if (key == 'back') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
        return;
      }
      if (key == '.') return; // whole units only
      if (_input.length >= 5) return;
      _input += key;
    });
  }

  Future<void> _confirm() async {
    final quantity = _quantity;
    if (quantity == null || quantity <= 0 || _submitting) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(restockControllerProvider)
          .commitProductRestock(widget.product.id, quantity);
      if (mounted) Navigator.of(context).pop();
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
    final quantity = _quantity;
    final currentStock = widget.product.stockCount;
    final newStock = currentStock + (quantity ?? 0);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: KeypadEntryLayout(
            display: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.product.name, style: AppTextStyles.headingMd),
                Text(
                  'Current stock: $currentStock',
                  style: AppTextStyles.secondary(AppTextStyles.bodySm),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Quantity delivered',
                  style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _input.isEmpty ? '0' : _input,
                  style: AppTextStyles.numericXl,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  quantity == null || quantity <= 0
                      ? 'This adds to the existing stock — it never replaces it.'
                      : 'New stock: $newStock',
                  style: (quantity == null || quantity <= 0)
                      ? AppTextStyles.muted(AppTextStyles.bodySm)
                      : AppTextStyles.success(AppTextStyles.bodySm),
                ),
              ],
            ),
            keypad: NumericKeypad(onKeyTap: _tapKey),
            action: AppButton(
              label: 'Add to stock',
              loading: _submitting,
              onPressed: (quantity != null && quantity > 0 && !_submitting)
                  ? _confirm
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
