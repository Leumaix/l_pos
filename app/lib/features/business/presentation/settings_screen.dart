import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../application/business_providers.dart';
import '../application/settings_controller.dart';

/// Owner-only. Deliberately just the gas tank capacity for now — it only
/// feeds the Stock screen's "% full" gauge, so it's low-risk to make
/// editable on its own. The gas RATE stays console-only: it's pegged to
/// how stock is tracked internally (in "units"), so changing it needs to
/// correctly recompute existing stock to preserve the actual physical kg
/// — its own task, with its own careful verification.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentCapacityKg = ref.watch(gasTankCapacityKgProvider);
    final state = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: AppColors.background),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 560,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
