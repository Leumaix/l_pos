import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../application/shift_controller.dart';
import '../application/shift_providers.dart';

/// Any active staff member can close — not owner-only. Counts the actual
/// drawer against what the shift's own running totals say it should
/// hold (opening float + cash sales only — card/transfer/credit sales
/// never touched this physical drawer).
class CloseDayScreen extends ConsumerWidget {
  final VoidCallback onClosed;

  const CloseDayScreen({super.key, required this.onClosed});

  Future<void> _handleClose(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(closeDayControllerProvider.notifier);
    final preview = await controller.preparePreview();
    if (preview == null) return; // invalid input or nothing open — error already set
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close the day?'),
        content: Text(
          'Expected ${formatNaira(preview.expectedCashNaira)} in the drawer '
          '(${formatNaira(preview.shift.openingFloatNaira)} float + '
          '${formatNaira(preview.shift.cashTotalNaira)} cash sales).\n\n'
          'You counted ${formatNaira(preview.countedCashNaira)} — '
          '${formatVariance(preview.varianceNaira)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await controller.confirmClose(preview);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shiftAsync = ref.watch(currentShiftProvider);
    final state = ref.watch(closeDayControllerProvider);
    final controller = ref.read(closeDayControllerProvider.notifier);

    ref.listen(closeDayControllerProvider, (previous, next) {
      if (next.justClosed) onClosed();
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Close the day'), backgroundColor: AppColors.background),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          // Same reasoning as Open Day: a data-entry form stays a sane,
          // readable width at every viewport size — no desktopMaxWidth.
          child: ResponsiveCenter(
            maxWidth: 560,
            child: shiftAsync.when(
              data: (shift) {
                if (shift == null) {
                  return Text(
                    'No shift is currently open.',
                    style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SummaryRow(label: 'Opening float', value: formatNaira(shift.openingFloatNaira)),
                          _SummaryRow(label: 'Cash sales', value: formatNaira(shift.cashTotalNaira)),
                          _SummaryRow(label: 'Card sales', value: formatNaira(shift.cardTotalNaira)),
                          _SummaryRow(label: 'Transfer sales', value: formatNaira(shift.transferTotalNaira)),
                          _SummaryRow(
                            label: 'Customer account sales',
                            value: formatNaira(shift.creditTotalNaira),
                          ),
                          _SummaryRow(label: 'Sales rung up', value: '${shift.salesCount}', isLast: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Count the drawer', style: AppTextStyles.headingSm),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Only cash sales affect what the drawer should hold — card, transfer, and '
                      'customer-account sales never put physical cash in it.',
                      style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Counted cash (₦)', style: AppTextStyles.labelMd),
                          const SizedBox(height: AppSpacing.xs),
                          TextField(
                            enabled: !state.submitting,
                            keyboardType: TextInputType.number,
                            onChanged: controller.setCountedCashInput,
                            decoration: const InputDecoration(hintText: '0'),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SizedBox(
                            height: 20,
                            child: state.errorMessage != null
                                ? Text(state.errorMessage!, style: AppTextStyles.danger(AppTextStyles.bodySm))
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppButton(
                            label: 'Close the day',
                            loading: state.submitting,
                            onPressed: state.countedCashInput.trim().isEmpty
                                ? null
                                : () => _handleClose(context, ref),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              ),
              error: (err, _) =>
                  Text('Could not load the shift', style: AppTextStyles.danger(AppTextStyles.bodyMd)),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _SummaryRow({required this.label, required this.value, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.secondary(AppTextStyles.bodyMd),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(value, style: AppTextStyles.numericSm),
        ],
      ),
    );
  }
}
