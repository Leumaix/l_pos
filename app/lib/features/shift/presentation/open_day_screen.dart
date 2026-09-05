import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../application/shift_controller.dart';

/// Any active staff member can open — not owner-only. Declares the
/// starting cash float; nothing else about the day needs entering here,
/// the running per-method totals accumulate on their own as sales happen.
class OpenDayScreen extends ConsumerWidget {
  final VoidCallback onOpened;

  const OpenDayScreen({super.key, required this.onOpened});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(openDayControllerProvider);
    final controller = ref.read(openDayControllerProvider.notifier);

    ref.listen(openDayControllerProvider, (previous, next) {
      if (next.justOpened) onOpened();
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Open the day'), backgroundColor: AppColors.background),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Starting cash float', style: AppTextStyles.headingSm),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The cash you\'re starting the drawer with. This is scoped to the whole '
                'business day, not just your shift — it stays open until someone closes it '
                'tonight, no matter who\'s handling sales in between.',
                style: AppTextStyles.secondary(AppTextStyles.bodyMd),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Starting float (₦)', style: AppTextStyles.labelMd),
                    const SizedBox(height: AppSpacing.xs),
                    TextField(
                      enabled: !state.submitting,
                      keyboardType: TextInputType.number,
                      onChanged: controller.setFloatInput,
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
                      label: 'Open the day',
                      loading: state.submitting,
                      onPressed: state.floatInput.trim().isEmpty ? null : controller.openDay,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
