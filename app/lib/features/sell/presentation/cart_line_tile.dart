import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../domain/cart_line.dart';

/// One cart line's row — a gas or product line, with quantity steppers
/// for a product line and a remove button. Shared by the narrow-mode
/// cart bottom sheet and the wide-mode Sell rail so both render the
/// exact same gas/product/stock-limit logic, never two copies of it.
class CartLineTile extends StatelessWidget {
  final CartLine line;
  final VoidCallback onRemove;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  const CartLineTile({
    super.key,
    required this.line,
    required this.onRemove,
    this.onIncrement,
    this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final gasLine = line is GasCartLine ? line as GasCartLine : null;
    final productLine = line is ProductCartLine
        ? line as ProductCartLine
        : null;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.name, style: AppTextStyles.bodyLg),
              if (gasLine?.oversells ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Stock will go negative',
                    style: AppTextStyles.danger(AppTextStyles.bodySm),
                  ),
                ),
            ],
          ),
        ),
        if (productLine != null) ...[
          CartLineStepperButton(icon: Icons.remove, onTap: onDecrement),
          SizedBox(
            width: 28,
            child: Text(
              '${productLine.quantity}',
              textAlign: TextAlign.center,
              style: AppTextStyles.labelMd,
            ),
          ),
          CartLineStepperButton(icon: Icons.add, onTap: onIncrement),
          const SizedBox(width: AppSpacing.sm),
        ],
        SizedBox(
          width: 84,
          child: Text(
            formatNaira(line.lineTotal),
            textAlign: TextAlign.right,
            style: AppTextStyles.numericSm,
          ),
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class CartLineStepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const CartLineStepperButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled ? AppColors.textPrimary : AppColors.textFaint,
        ),
      ),
    );
  }
}
