import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../application/admin_auth_controller.dart';

/// Plain email-link sign-in for the super-admin tool — no PIN keypad, no
/// device-verification framing (there's no shared device here, no staff
/// roster this identity belongs to). Renders differently per
/// [AdminAuthStage] rather than separate routes, same shape as the
/// mobile app's VerifyEmailScreen, since a page reload mid-flow (closing
/// the tab between sending the link and opening it) can land on any
/// stage.
class AdminLoginScreen extends ConsumerWidget {
  const AdminLoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminAuthControllerProvider);
    final controller = ref.read(adminAuthControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
            child: ResponsiveCenter(maxWidth: 440, child: _buildStage(state, controller)),
          ),
        ),
      ),
    );
  }

  Widget _buildStage(AdminAuthState state, AdminAuthController controller) {
    switch (state.stage) {
      case AdminAuthStage.form:
      case AdminAuthStage.sending:
        return _EmailForm(state: state, controller: controller);
      case AdminAuthStage.linkSent:
        return _LinkSent(state: state, controller: controller);
      case AdminAuthStage.completingLink:
        return const _Working(message: 'Confirming your email…');
      case AdminAuthStage.done:
        return const _Working(message: 'Signed in…');
    }
  }
}

class _EmailForm extends StatefulWidget {
  final AdminAuthState state;
  final AdminAuthController controller;

  const _EmailForm({required this.state, required this.controller});

  @override
  State<_EmailForm> createState() => _EmailFormState();
}

class _EmailFormState extends State<_EmailForm> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.state.email);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sending = widget.state.stage == AdminAuthStage.sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.admin_panel_settings_outlined, size: 48, color: AppColors.accent),
        const SizedBox(height: AppSpacing.lg),
        Text('Leumadepos admin', style: AppTextStyles.headingLg, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Sign in to onboard a new business.',
          style: AppTextStyles.secondary(AppTextStyles.bodyMd),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxl),
        TextField(
          controller: _textController,
          keyboardType: TextInputType.emailAddress,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyLg,
          enabled: !sending,
          onChanged: widget.controller.setEmail,
          decoration: const InputDecoration(hintText: 'Email'),
        ),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: widget.state.errorMessage != null
              ? Text(
                  widget.state.errorMessage!,
                  style: AppTextStyles.danger(AppTextStyles.bodySm),
                  textAlign: TextAlign.center,
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Send link',
          loading: sending,
          onPressed: widget.state.email.trim().isEmpty ? null : widget.controller.sendLink,
        ),
      ],
    );
  }
}

class _LinkSent extends StatelessWidget {
  final AdminAuthState state;
  final AdminAuthController controller;

  const _LinkSent({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 48, color: AppColors.accent),
        const SizedBox(height: AppSpacing.lg),
        Text('Check your email', style: AppTextStyles.headingLg, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'We sent a link to ${state.email}. Open it in THIS browser to finish signing in.',
          style: AppTextStyles.secondary(AppTextStyles.bodyMd),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Check your inbox — and your spam or junk folder — for an email from us.',
          style: AppTextStyles.accent(AppTextStyles.bodySm),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: state.errorMessage != null
              ? Text(state.errorMessage!, style: AppTextStyles.danger(AppTextStyles.bodySm), textAlign: TextAlign.center)
              : null,
        ),
        const SizedBox(height: AppSpacing.xl),
        TextButton(
          onPressed: controller.sendLink,
          child: Text('Resend link', style: AppTextStyles.accent(AppTextStyles.bodyMd)),
        ),
      ],
    );
  }
}

class _Working extends StatelessWidget {
  final String message;

  const _Working({required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const CircularProgressIndicator(color: AppColors.accent),
        const SizedBox(height: AppSpacing.lg),
        Text(message, style: AppTextStyles.secondary(AppTextStyles.bodyMd)),
      ],
    );
  }
}
