import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../application/web_auth_controller.dart';

/// Email+password sign-up/login for the web/PWA build — no PIN keypad, no
/// shared-device handoff concerns (each staff member has their own browser
/// session here). Same shape as the admin tool's AdminLoginScreen, adapted
/// for staff rather than the platform operator. Renders differently per
/// [WebAuthStage] rather than separate routes, so a page reload mid-flow
/// can land on any stage.
class WebLoginScreen extends ConsumerWidget {
  const WebLoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(webAuthControllerProvider);
    final controller = ref.read(webAuthControllerProvider.notifier);

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

  Widget _buildStage(WebAuthState state, WebAuthController controller) {
    switch (state.stage) {
      case WebAuthStage.form:
      case WebAuthStage.submitting:
        return _CredentialsForm(state: state, controller: controller);
      case WebAuthStage.awaitingVerification:
        return _AwaitingVerification(state: state, controller: controller);
      case WebAuthStage.completingSignUp:
        return const _Working(message: 'Finishing sign-up…');
      case WebAuthStage.done:
        return const _Working(message: 'Signed in…');
    }
  }
}

class _CredentialsForm extends StatefulWidget {
  final WebAuthState state;
  final WebAuthController controller;

  const _CredentialsForm({required this.state, required this.controller});

  @override
  State<_CredentialsForm> createState() => _CredentialsFormState();
}

class _CredentialsFormState extends State<_CredentialsForm> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.state.email);
    _passwordController = TextEditingController(text: widget.state.password);
  }

  @override
  void didUpdateWidget(covariant _CredentialsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Toggling sign-up/sign-in clears the password field in the
    // controller — mirror that here so a stale value never lingers on
    // screen after the switch.
    if (widget.state.password.isEmpty && _passwordController.text.isNotEmpty) {
      _passwordController.clear();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final submitting = widget.state.stage == WebAuthStage.submitting;
    final isSignUp = widget.state.isSignUpMode;
    final canSubmit = widget.state.email.trim().isNotEmpty && widget.state.password.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.storefront_outlined, size: 48, color: AppColors.accent),
        const SizedBox(height: AppSpacing.lg),
        Text('Leumadepos', style: AppTextStyles.headingLg, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        Text(
          isSignUp ? 'Create your account.' : 'Sign in with your email and password.',
          style: AppTextStyles.secondary(AppTextStyles.bodyMd),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxl),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyLg,
          enabled: !submitting,
          onChanged: widget.controller.setEmail,
          decoration: const InputDecoration(hintText: 'Email'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _passwordController,
          obscureText: true,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyLg,
          enabled: !submitting,
          onChanged: widget.controller.setPassword,
          decoration: const InputDecoration(hintText: 'Password'),
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
          label: isSignUp ? 'Create account' : 'Sign in',
          loading: submitting,
          onPressed: canSubmit ? (isSignUp ? widget.controller.signUp : widget.controller.signIn) : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextButton(
          onPressed: submitting ? null : widget.controller.toggleSignUpMode,
          child: Text(
            isSignUp ? 'Already have an account? Sign in' : 'New staff member? Create an account',
            style: AppTextStyles.secondary(AppTextStyles.bodyMd),
          ),
        ),
      ],
    );
  }
}

class _AwaitingVerification extends StatelessWidget {
  final WebAuthState state;
  final WebAuthController controller;

  const _AwaitingVerification({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 48, color: AppColors.accent),
        const SizedBox(height: AppSpacing.lg),
        Text('Check your email', style: AppTextStyles.headingLg, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'We sent a one-time verification link to ${state.email}. Click it, then come back here and continue.',
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
        AppButton(label: "I've verified — Continue", onPressed: controller.checkVerificationAndContinue),
        const SizedBox(height: AppSpacing.lg),
        TextButton(
          onPressed: controller.resendVerificationEmail,
          child: Text('Resend email', style: AppTextStyles.accent(AppTextStyles.bodyMd)),
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
