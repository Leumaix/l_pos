import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gas_stock/gas_stock.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/keypad_entry_layout.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../application/cart_controller.dart';
import '../application/inventory_providers.dart';
import '../domain/cart_line.dart';

/// The gas entry overlay: two modes (by kg / by amount), a numpad, and a
/// live conversion preview. Adding is never blocked for gas — an oversell
/// just surfaces a warning, per the business's oversell policy.
Future<void> showGasNumpadSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.cardRadius),
      ),
    ),
    builder: (context) => const _GasNumpadSheet(),
  );
}

class _GasNumpadSheet extends ConsumerStatefulWidget {
  const _GasNumpadSheet();

  @override
  ConsumerState<_GasNumpadSheet> createState() => _GasNumpadSheetState();
}

class _GasNumpadSheetState extends ConsumerState<_GasNumpadSheet> {
  GasSaleMode _mode = GasSaleMode.kg;
  String _input = '';

  num? get _value => _input.isEmpty ? null : num.tryParse(_input);

  void _tapKey(String key) {
    setState(() {
      if (key == 'back') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
        return;
      }
      if (key == '.' && (_input.contains('.') || _mode == GasSaleMode.amount))
        return;
      if (_input.length >= 8) return;
      _input += key;
    });
  }

  void _switchMode(GasSaleMode mode) {
    setState(() {
      _mode = mode;
      _input = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final rate = ref.watch(gasRateProvider);
    final gasStockAsync = ref.watch(gasStockProvider);
    final value = _value;

    // Named so the exact same callback wires both the on-screen "Add to
    // cart" button and KeypadEntryLayout's physical-keyboard Enter —
    // one source of truth, not two copies of the enabled condition that
    // could drift apart.
    final VoidCallback? onAddToCart = (value != null && value > 0)
        ? () {
            final gasStock = gasStockAsync.valueOrNull;
            if (gasStock == null) return;
            final controller = ref.read(cartControllerProvider.notifier);
            final result = _mode == GasSaleMode.kg
                ? controller.addGasKg(
                    kg: value,
                    currentGasStock: gasStock,
                    rate: rate,
                  )
                : controller.addGasAmount(
                    amountNaira: value.round(),
                    currentGasStock: gasStock,
                  );
            Navigator.of(context).pop();
            if (result.message != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message!),
                  backgroundColor: AppColors.dangerBg,
                ),
              );
            }
          }
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
                Text('Cooking Gas', style: AppTextStyles.headingMd),
                Text(
                  '${formatNaira(rate.nairaPerKg.round())}/kg',
                  style: AppTextStyles.secondary(AppTextStyles.bodySm),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: _ModeChip(
                        label: 'By kg',
                        selected: _mode == GasSaleMode.kg,
                        onTap: () => _switchMode(GasSaleMode.kg),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _ModeChip(
                        label: 'By amount',
                        selected: _mode == GasSaleMode.amount,
                        onTap: () => _switchMode(GasSaleMode.amount),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _input.isEmpty
                      ? (_mode == GasSaleMode.kg ? '0 kg' : formatNaira(0))
                      : (_mode == GasSaleMode.kg
                            ? '$_input kg'
                            : formatNaira(int.tryParse(_input) ?? 0)),
                  style: AppTextStyles.numericXl,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  value == null || value <= 0
                      ? ' '
                      : (_mode == GasSaleMode.kg
                            ? '= ${formatNaira(unitsForKg(value, rate))}'
                            : '≈ ${formatKg(displayKgForAmount(value.round(), rate))}'),
                  style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                ),
                const SizedBox(height: AppSpacing.md),
                gasStockAsync.maybeWhen(
                  data: (stock) {
                    if (value == null || value <= 0)
                      return const SizedBox(height: 20);
                    final unitsNeeded = _mode == GasSaleMode.kg
                        ? unitsForKg(value, rate)
                        : value.round();
                    if (!wouldGoNegative(stock, unitsNeeded))
                      return const SizedBox(height: 20);
                    return Text(
                      'This will take gas stock negative',
                      style: AppTextStyles.danger(AppTextStyles.bodySm),
                    );
                  },
                  orElse: () => const SizedBox(height: 20),
                ),
              ],
            ),
            keypad: NumericKeypad(
              onKeyTap: _tapKey,
              showDecimal: _mode == GasSaleMode.kg,
            ),
            action: AppButton(
              label: 'Add to cart',
              onPressed: onAddToCart,
            ),
            onKeyTap: _tapKey,
            onSubmit: onAddToCart,
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentTintBg : AppColors.background,
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        child: Container(
          height: AppSpacing.minTouchTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMd.copyWith(
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
