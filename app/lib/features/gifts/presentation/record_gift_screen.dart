import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../../../core/widgets/pin_dots.dart';
import '../../sell/application/inventory_providers.dart';
import '../../sell/domain/product.dart';
import '../application/record_gift_controller.dart';
import '../domain/gift.dart';

/// Any active staff member can record a gift — not owner-only, matching
/// how selling/restocking/expenses already work. Every gift needs an
/// open shift (see GiftController) — unlike RecordExpenseScreen, there's
/// no method that skips this.
class RecordGiftScreen extends ConsumerWidget {
  final VoidCallback onRecorded;

  const RecordGiftScreen({super.key, required this.onRecorded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordGiftControllerProvider);
    final controller = ref.read(recordGiftControllerProvider.notifier);
    final evaluation = controller.evaluation;

    ref.listen(recordGiftControllerProvider, (previous, next) {
      if (next.justRecorded) onRecorded();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gift stock'),
        backgroundColor: AppColors.background,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What are you giving away?',
                  style: AppTextStyles.headingSm,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    for (final itemType in GiftItemType.values) ...[
                      Expanded(
                        child: _ItemTypeTile(
                          label: itemType == GiftItemType.gas
                              ? 'Gas'
                              : 'Product',
                          selected: state.itemType == itemType,
                          onTap: () => controller.setItemType(itemType),
                        ),
                      ),
                      if (itemType != GiftItemType.values.last)
                        const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                ),
                if (state.itemType == GiftItemType.product) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Text('Which product?', style: AppTextStyles.headingSm),
                  const SizedBox(height: AppSpacing.sm),
                  _ProductPicker(
                    selectedProductId: state.productId,
                    onSelect: controller.setProduct,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text(
                  state.itemType == GiftItemType.gas
                      ? 'Quantity (kg)'
                      : 'Quantity',
                  style: AppTextStyles.headingSm,
                ),
                const SizedBox(height: AppSpacing.md),
                _QuantitySection(
                  input: state.quantityInput,
                  showDecimal: state.itemType == GiftItemType.gas,
                  unit: state.itemType == GiftItemType.gas ? 'kg' : null,
                  onKeyTap: controller.onQuantityKey,
                ),
                if (evaluation != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Estimated value: ${formatNaira(evaluation.estimatedValueNaira)}',
                    style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text('Reason', style: AppTextStyles.headingSm),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  enabled: !state.submitting,
                  onChanged: controller.setReason,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Sample for a new customer',
                  ),
                ),
                if (evaluation != null && evaluation.requiresApproval) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _OwnerApprovalSection(
                    ownerEmail: state.ownerEmail,
                    ownerPin: state.ownerPin,
                    onEmailChanged: controller.setOwnerEmail,
                    onPinKeyTap: controller.tapOwnerPinKey,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: 20,
                  child: state.errorMessage != null
                      ? Text(
                          state.errorMessage!,
                          style: AppTextStyles.danger(AppTextStyles.bodySm),
                        )
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Record gift',
                  loading: state.submitting,
                  onPressed: controller.canSubmit ? controller.submit : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemTypeTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ItemTypeTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMd.copyWith(
              color: selected ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductPicker extends ConsumerWidget {
  final String? selectedProductId;
  final ValueChanged<String> onSelect;

  const _ProductPicker({
    required this.selectedProductId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    return productsAsync.when(
      data: (products) => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final product in products)
            _ProductChip(
              product: product,
              selected: product.id == selectedProductId,
              onTap: () => onSelect(product.id),
            ),
        ],
      ),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      ),
      error: (err, _) => Text(
        'Could not load products',
        style: AppTextStyles.danger(AppTextStyles.bodySm),
      ),
    );
  }
}

class _ProductChip extends StatelessWidget {
  final Product product;
  final bool selected;
  final VoidCallback onTap;

  const _ProductChip({
    required this.product,
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            '${product.name} (${formatNaira(product.price)})',
            style: AppTextStyles.labelMd.copyWith(
              color: selected ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuantitySection extends StatelessWidget {
  final String input;
  final bool showDecimal;
  final String? unit;
  final ValueChanged<String> onKeyTap;

  const _QuantitySection({
    required this.input,
    required this.showDecimal,
    required this.unit,
    required this.onKeyTap,
  });

  @override
  Widget build(BuildContext context) {
    final display = input.isEmpty ? '0' : input;
    return Column(
      children: [
        Text(
          unit == null ? display : '$display $unit',
          style: AppTextStyles.numericXl,
        ),
        const SizedBox(height: AppSpacing.lg),
        NumericKeypad(onKeyTap: onKeyTap, showDecimal: showDecimal),
      ],
    );
  }
}

/// Only shown once the gift crosses the approval threshold — the owner
/// types their OWN email + PIN, right here on the attendant's device,
/// without ever switching the app's active signed-in user. See
/// AuthRepository.verifyActiveOwnerPin's own doc comment for the
/// mechanism; the active session staying the attendant's throughout is
/// the entire point, not an incidental detail.
class _OwnerApprovalSection extends StatelessWidget {
  final String ownerEmail;
  final String ownerPin;
  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String> onPinKeyTap;

  const _OwnerApprovalSection({
    required this.ownerEmail,
    required this.ownerPin,
    required this.onEmailChanged,
    required this.onPinKeyTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This gift needs the owner\'s approval',
            style: AppTextStyles.headingSm,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Hand the device to the owner to enter their own email and PIN.',
            style: AppTextStyles.secondary(AppTextStyles.bodyMd),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            keyboardType: TextInputType.emailAddress,
            onChanged: onEmailChanged,
            decoration: const InputDecoration(hintText: "Owner's email"),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(child: PinDots(filled: ownerPin.length)),
          const SizedBox(height: AppSpacing.lg),
          NumericKeypad(onKeyTap: onPinKeyTap, maxWidth: 300),
        ],
      ),
    );
  }
}
