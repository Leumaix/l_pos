import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../sell/application/inventory_providers.dart';
import '../application/business_providers.dart';
import '../application/settings_controller.dart';

/// Owner-only. Gas tank capacity only feeds the Stock screen's "% full"
/// gauge, so it's a plain field swap. The gas RATE is more careful:
/// stock is tracked internally in "units" pegged to it, so a rate change
/// has to atomically recompute units to preserve the actual physical kg
/// — see GasRateController.confirmRateChange and
/// FirebaseInventoryRepository.changeGasRate.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _handleSaveRate(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(gasRateControllerProvider.notifier);
    final preview = await controller.preparePreview();
    if (preview == null) return; // invalid input — error already set
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change gas rate?'),
        content: Text(
          'Changing rate from ${formatNaira(preview.oldRate.nairaPerKg.round())} to '
          '${formatNaira(preview.newRate.nairaPerKg.round())}/kg — your current '
          '${formatKg(preview.preservedKg)} in stock will still read as '
          '${formatKg(preview.preservedKg)} after this change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Change rate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await controller.confirmRateChange(preview.newRate);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentCapacityKg = ref.watch(gasTankCapacityKgProvider);
    final state = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    final currentRate = ref.watch(gasRateProvider);
    final rateState = ref.watch(gasRateControllerProvider);
    final rateController = ref.read(gasRateControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: AppColors.background),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 560,
            desktopMaxWidth: 880,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gas tank capacity', style: AppTextStyles.headingSm),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Sets what "100% full" means on the Stock screen\'s gauge — it '
                  'doesn\'t change how gas stock itself is tracked.',
                  style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Current capacity',
                              style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(formatKg(currentCapacityKg), style: AppTextStyles.numericMd),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text('New capacity (kg)', style: AppTextStyles.labelMd),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        enabled: !state.submitting,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: controller.setCapacityInput,
                        decoration: InputDecoration(hintText: currentCapacityKg.round().toString()),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        height: 20,
                        child: state.errorMessage != null
                            ? Text(state.errorMessage!, style: AppTextStyles.danger(AppTextStyles.bodySm))
                            : (state.justSaved
                                  ? Text('Saved.', style: AppTextStyles.success(AppTextStyles.bodySm))
                                  : null),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        label: 'Save',
                        loading: state.submitting,
                        onPressed: state.capacityInput.trim().isEmpty ? null : controller.saveGasTankCapacity,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text('Gas rate', style: AppTextStyles.headingSm),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Changes what a naira of gas is worth going forward. Stock on '
                  'hand is automatically re-expressed at the new rate so the '
                  'physical kg you have never changes — only how it\'s recorded.',
                  style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Current rate',
                              style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${formatNaira(currentRate.nairaPerKg.round())}/kg',
                            style: AppTextStyles.numericMd,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text('New rate (₦/kg)', style: AppTextStyles.labelMd),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        enabled: !rateState.submitting,
                        keyboardType: TextInputType.number,
                        onChanged: rateController.setRateInput,
                        decoration: InputDecoration(hintText: currentRate.nairaPerKg.round().toString()),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        height: 20,
                        child: rateState.errorMessage != null
                            ? Text(rateState.errorMessage!, style: AppTextStyles.danger(AppTextStyles.bodySm))
                            : (rateState.justSaved
                                  ? Text('Saved.', style: AppTextStyles.success(AppTextStyles.bodySm))
                                  : null),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        label: 'Save',
                        loading: rateState.submitting,
                        onPressed: rateState.rateInput.trim().isEmpty
                            ? null
                            : () => _handleSaveRate(context, ref),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
