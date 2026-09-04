import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/keypad_entry_layout.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../../../core/widgets/pin_dots.dart';
import '../application/login_controller.dart';
import '../application/verification_controller.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loginControllerProvider);
    final controller = ref.read(loginControllerProvider.notifier);

    Future<void> handleSubmit() async {
      final result = await controller.submit();
      // On success, navigation to Home happens via the router listening
      // to auth state — see app_router.dart.
      if (result == LoginSubmitResult.needsVerification && context.mounted) {
        ref
            .read(verificationControllerProvider.notifier)
            .start(prefillEmail: state.email.trim());
        context.push('/verify-email');
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xl,
          ),
          child: KeypadEntryLayout(
            display: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.xxl),
                const _LogoBadge(),
                const SizedBox(height: AppSpacing.lg),
                Text('Leumadepos', style: AppTextStyles.headingLg),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Sign in to start selling',
                  style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                ),
                const SizedBox(height: AppSpacing.xxl),
                TextField(
                  keyboardType: TextInputType.emailAddress,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLg,
                  onChanged: controller.setEmail,
                  decoration: const InputDecoration(hintText: 'Email'),
                ),
                const SizedBox(height: AppSpacing.xl),
                PinDots(filled: state.pin.length),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 20,
                  child: state.errorMessage != null
                      ? Text(
                          state.errorMessage!,
                          style: AppTextStyles.danger(AppTextStyles.bodySm),
                        )
                      : null,
                ),
              ],
            ),
            keypad: NumericKeypad(onKeyTap: controller.tapKey),
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(
                  label: 'Sign in',
                  loading: state.submitting,
                  onPressed: state.canSubmit ? handleSubmit : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextButton(
                  onPressed: state.submitting
                      ? null
                      : () {
                          ref
                              .read(verificationControllerProvider.notifier)
                              .start(prefillEmail: state.email.trim());
                          context.push('/verify-email');
                        },
                  child: Text(
                    'First time on this device? Verify by email',
                    style: AppTextStyles.secondary(AppTextStyles.bodyMd),
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

class _LogoBadge extends StatelessWidget {
  const _LogoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: const BoxDecoration(
        gradient: AppColors.accentGradient,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.local_fire_department,
        color: AppColors.onAccent,
        size: 36,
      ),
    );
  }
}
