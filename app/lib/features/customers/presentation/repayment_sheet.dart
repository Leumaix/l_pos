import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/keypad_entry_layout.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../application/customer_providers.dart';
import '../domain/customer.dart';

/// Numpad overlay for "Record payment" — a direct balance adjustment, no
/// cart or stock involved, since a cash repayment genuinely doesn't touch
/// inventory. Allowed to take the balance negative (store credit), never
/// clamped at zero. This is the only manual ledger entry left on Customer
/// detail — "Record sale" goes through the real Sell → Payment flow
/// instead, since a credit sale does affect stock.
Future<void> showRepaymentSheet(
  BuildContext context, {
  required Customer customer,
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
    builder: (context) => _RepaymentSheet(customer: customer),
  );
}

class _RepaymentSheet extends ConsumerStatefulWidget {
  final Customer customer;

  const _RepaymentSheet({required this.customer});

  @override
  ConsumerState<_RepaymentSheet> createState() => _RepaymentSheetState();
}

class _RepaymentSheetState extends ConsumerState<_RepaymentSheet> {
  String _input = '';
  bool _submitting = false;

  int? get _amount => _input.isEmpty ? null : int.tryParse(_input);

  void _tapKey(String key) {
    setState(() {
      if (key == 'back') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
        return;
      }
      if (key == '.') return; // whole naira only
      if (_input.length >= 9) return;
      _input += key;
    });
  }

  Future<void> _confirm() async {
    final amount = _amount;
    if (amount == null || amount <= 0 || _submitting) return;

    setState(() => _submitting = true);
    await ref
        .read(customerRepositoryProvider)
        .recordRepayment(customerId: widget.customer.id, amountNaira: amount);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final amount = _amount;
    final newBalance = widget.customer.balance - (amount ?? 0);
    // Named so the button's onPressed and KeypadEntryLayout's physical-
    // keyboard Enter share the exact same enabled condition and
    // callback, rather than two copies that could drift apart.
    final VoidCallback? onRecordPayment = (amount != null && amount > 0 && !_submitting)
        ? _confirm
        : null;

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
                Text('Record payment', style: AppTextStyles.headingMd),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.customer.name,
                  style: AppTextStyles.secondary(AppTextStyles.bodySm),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _input.isEmpty ? formatNaira(0) : formatNaira(amount ?? 0),
                  style: AppTextStyles.numericXl,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  amount == null || amount <= 0
                      ? ' '
                      : 'New balance: ${formatNaira(newBalance)}',
                  style: (newBalance < 0
                      ? AppTextStyles.success
                      : AppTextStyles.secondary)(AppTextStyles.bodyMd),
                ),
              ],
            ),
            keypad: NumericKeypad(onKeyTap: _tapKey),
            onKeyTap: _tapKey,
            onSubmit: onRecordPayment,
            action: AppButton(
              label: 'Record payment',
              loading: _submitting,
              onPressed: onRecordPayment,
            ),
          ),
        ),
      ),
    );
  }
}
