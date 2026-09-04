import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../application/cart_controller.dart';
import '../domain/cart_line.dart';
import 'cart_line_tile.dart';

Future<void> showCartSheet(
  BuildContext context, {
  required VoidCallback onGoToPayment,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.cardRadius),
      ),
    ),
    builder: (context) => _CartSheet(onGoToPayment: onGoToPayment),
  );
}

class _CartSheet extends ConsumerWidget {
  final VoidCallback onGoToPayment;

  const _CartSheet({required this.onGoToPayment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final controller = ref.read(cartControllerProvider.notifier);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cart', style: AppTextStyles.headingMd),
            const SizedBox(height: AppSpacing.md),
            if (cart.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: Text(
                    'Cart is empty',
                    style: AppTextStyles.muted(AppTextStyles.bodyMd),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cart.lines.length,
                  separatorBuilder: (_, _) => const Divider(
                    color: AppColors.border,
                    height: AppSpacing.lg,
                  ),
                  itemBuilder: (context, index) {
                    final line = cart.lines[index];
                    final productLine = line is ProductCartLine ? line : null;
                    // Disabled proactively, not just blocked reactively: a
                    // SnackBar raised from inside this modal sheet renders
                    // behind the sheet's own overlay and is invisible, so
                    // the only correct feedback here is to never let the
                    // tap fire once a line is already at its stock limit.
                    final atStockLimit =
                        productLine != null &&
                        productLine.quantity >= productLine.product.stockCount;

                    return CartLineTile(
                      line: line,
                      onRemove: () => controller.removeCartLine(line.id),
                      onIncrement: productLine != null && !atStockLimit
                          ? () => controller.addCartProduct(productLine.product)
                          : null,
                      onDecrement: productLine != null
                          ? () => controller.decrementCartProduct(line.id)
                          : null,
                    );
                  },
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(color: AppColors.border),
            const SizedBox(height: AppSpacing.md),
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
              onPressed: cart.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      onGoToPayment();
                    },
            ),
          ],
        ),
      ),
    );
  }
}
