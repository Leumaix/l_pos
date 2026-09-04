import 'package:flutter/material.dart';

import '../responsive/breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A reusable numeric keypad: digits 0-9, backspace, and an optional
/// decimal point. Stateless — the caller owns the entered value and
/// receives each keypress via [onKeyTap]. Used by Login (PIN, no decimal),
/// the Sell numpad overlay (kg/amount, decimal), the Payment cash numpad,
/// and the Restock kg numpad.
///
/// Capped to a comfortable width and centered on tablet, rather than
/// stretching keys edge-to-edge — see [Breakpoints].
class NumericKeypad extends StatelessWidget {
  final ValueChanged<String> onKeyTap;
  final bool showDecimal;
  final double maxWidth;

  const NumericKeypad({
    super.key,
    required this.onKeyTap,
    this.showDecimal = false,
    this.maxWidth = 360,
  });

  static const _layout = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in _layout) _KeyRow(keys: row, onKeyTap: onKeyTap),
            _KeyRow(
              keys: [showDecimal ? '.' : '', '0', 'back'],
              onKeyTap: onKeyTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  final List<String> keys;
  final ValueChanged<String> onKeyTap;

  const _KeyRow({required this.keys, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [for (final key in keys) Expanded(child: _Key(value: key, onTap: onKeyTap))],
    );
  }
}

class _Key extends StatelessWidget {
  final String value;
  final ValueChanged<String> onTap;

  const _Key({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox(height: 72);

    return Padding(
      padding: const EdgeInsets.all(6),
      child: AspectRatio(
        aspectRatio: 1.4,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onTap(value),
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: value == 'back'
                  ? const Icon(Icons.backspace_outlined, color: AppColors.textPrimary, size: 22)
                  : Text(value, style: AppTextStyles.headingMd),
            ),
          ),
        ),
      ),
    );
  }
}
