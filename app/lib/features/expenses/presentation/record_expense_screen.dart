import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../application/record_expense_controller.dart';
import '../domain/expense.dart';

/// Any active staff member can record an expense — not owner-only,
/// matching how selling/restocking already work. Only a cash expense
/// touches the till (see ExpenseController); transfer/other are a record
/// only and need no shift open at all.
class RecordExpenseScreen extends ConsumerWidget {
  final VoidCallback onRecorded;

  const RecordExpenseScreen({super.key, required this.onRecorded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordExpenseControllerProvider);
    final controller = ref.read(recordExpenseControllerProvider.notifier);

    ref.listen(recordExpenseControllerProvider, (previous, next) {
      if (next.justRecorded) onRecorded();
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Record expense'), backgroundColor: AppColors.background),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          // Same reasoning as Open Day/Close Day/Invite Staff — a data-
          // entry form stays a sane, readable width at every viewport
          // size, not stretched edge-to-edge on a wide desktop window.
          child: ResponsiveCenter(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Amount', style: AppTextStyles.headingSm),
                const SizedBox(height: AppSpacing.md),
                _AmountSection(input: state.amountInput, onKeyTap: controller.onAmountKey),
                const SizedBox(height: AppSpacing.xl),
                Text('Paid by', style: AppTextStyles.headingSm),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    for (final method in ExpensePaymentMethod.values) ...[
                      Expanded(
                        child: _MethodTile(
                          label: _methodLabel(method),
                          selected: state.method == method,
                          onTap: () => controller.setMethod(method),
                        ),
                      ),
                      if (method != ExpensePaymentMethod.values.last) const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Category', style: AppTextStyles.headingSm),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final category in ExpenseCategory.values)
                      _CategoryChip(
                        label: _categoryLabel(category),
                        selected: state.category == category,
                        onTap: () => controller.setCategory(category),
                      ),
                  ],
                ),
                if (state.category == ExpenseCategory.other) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text('What was it?', style: AppTextStyles.labelMd),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    enabled: !state.submitting,
                    onChanged: controller.setNote,
                    decoration: const InputDecoration(hintText: 'e.g. Signboard repair'),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: 20,
                  child: state.errorMessage != null
                      ? Text(state.errorMessage!, style: AppTextStyles.danger(AppTextStyles.bodySm))
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Record expense',
                  loading: state.submitting,
                  onPressed: state.canSubmit ? controller.submit : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _methodLabel(ExpensePaymentMethod method) => switch (method) {
    ExpensePaymentMethod.cash => 'Cash',
    ExpensePaymentMethod.transfer => 'Transfer',
    ExpensePaymentMethod.other => 'Other',
  };

  String _categoryLabel(ExpenseCategory category) => switch (category) {
    ExpenseCategory.fuel => 'Fuel',
    ExpenseCategory.transport => 'Transport',
    ExpenseCategory.maintenance => 'Maintenance',
    ExpenseCategory.supplies => 'Supplies',
    ExpenseCategory.other => 'Other',
  };
}

class _AmountSection extends StatelessWidget {
  final String input;
  final ValueChanged<String> onKeyTap;

  const _AmountSection({required this.input, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    final amount = input.isEmpty ? 0 : (int.tryParse(input) ?? 0);
    return Column(
      children: [
        Text(formatNaira(amount), style: AppTextStyles.numericXl),
        const SizedBox(height: AppSpacing.lg),
        NumericKeypad(onKeyTap: onKeyTap),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MethodTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentTintBg : AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          height: AppSpacing.minTouchTarget + 8,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
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

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.selected, required this.onTap});

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
