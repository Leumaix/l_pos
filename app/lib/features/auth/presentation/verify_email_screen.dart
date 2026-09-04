import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../../../core/widgets/pin_dots.dart';
import '../application/verification_controller.dart';

/// One-time device verification, reached either from Login's "first time
/// on this device?" link or automatically when the email-link deep link
/// arrives (see main.dart). A single screen that renders differently per
/// [VerificationStage] rather than separate routes, since the deep link
/// can interrupt the flow at an unpredictable point (app closed between
/// sending the link and opening it).
class VerifyEmailScreen extends ConsumerWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(verificationControllerProvider);
    final controller = ref.read(verificationControllerProvider.notifier);

    // Only this exact transition — this flow's OWN session actually
    // becoming active — should leave this screen automatically. The
    // awaitingHandoff stage (another staff member still active) must
    // NOT auto-navigate, or the "ask them to sign out" message would
    // never be readable.
    ref.listen(verificationControllerProvider, (previous, next) {
      if (previous?.stage != VerificationStage.done && next.stage == VerificationStage.done) {
        context.go('/home');
      }
    });

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
          child: ResponsiveCenter(
            maxWidth: 440,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xxl),
                _buildStage(context, state, controller),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage(BuildContext context, VerificationState state, VerificationController controller) {
    switch (state.stage) {
      case VerificationStage.form:
      case VerificationStage.sending:
        return _EmailForm(state: state, controller: controller);
      case VerificationStage.linkSent:
        return _LinkSent(state: state, controller: controller);
      case VerificationStage.completingLink:
        return const _Working(message: 'Confirming your email…');
      case VerificationStage.choosingPin:
      case VerificationStage.confirmingPin:
        return _PinSetup(state: state, controller: controller);
      case VerificationStage.settingPin:
        return const _Working(message: 'Saving your PIN…');
      case VerificationStage.done:
        return const _Working(message: 'You\'re all set…');
      case VerificationStage.notAuthorized:
        return _NotAuthorized(controller: controller);
      case VerificationStage.awaitingHandoff:
        return _AwaitingHandoff(state: state);
    }
  }
}

class _NotAuthorized extends StatelessWidget {
  final VerificationController controller;

  const _NotAuthorized({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.block_outlined, size: 48, color: AppColors.danger),
        const SizedBox(height: AppSpacing.lg),
        Text('This device isn\'t set up for you', style: AppTextStyles.headingLg, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'That email checked out, but there\'s no staff account for it yet. Contact the owner to get added as staff.',
          style: AppTextStyles.secondary(AppTextStyles.bodyMd),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxl),
        AppButton(label: 'Try a different email', onPressed: () => controller.start()),
      ],
    );
  }
}

class _AwaitingHandoff extends StatelessWidget {
  final VerificationState state;

  const _AwaitingHandoff({required this.state});

  @override
  Widget build(BuildContext context) {
    final blockingUser = state.blockingUserName ?? 'the current user';
    return Column(
      children: [
        const Icon(Icons.check_circle_outline, size: 48, color: AppColors.success),
        const SizedBox(height: AppSpacing.lg),
        Text('Setup complete', style: AppTextStyles.headingLg, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Ask $blockingUser to sign out, then enter your PIN to start your shift.',
          style: AppTextStyles.secondary(AppTextStyles.bodyMd),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxl),
        AppButton(label: 'Continue to sign in', onPressed: () => context.go('/login')),
      ],
    );
  }
}

class _EmailForm extends StatefulWidget {
  final VerificationState state;
  final VerificationController controller;

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
  void didUpdateWidget(covariant _EmailForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only sync when the field is being cleared out from under the user
    // (e.g. "Use a different email") — never fight their own typing,
    // which already keeps state.email in step via onChanged.
    if (widget.state.email.isEmpty && _textController.text.isNotEmpty) {
      _textController.clear();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sending = widget.state.stage == VerificationStage.sending;
    return Column(
      children: [
        const Icon(Icons.mark_email_unread_outlined, size: 48, color: AppColors.accent),
        const SizedBox(height: AppSpacing.lg),
        Text('Verify this device', style: AppTextStyles.headingLg, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'First time signing in here. Enter your staff email and we\'ll send a one-time link to confirm it\'s you.',
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
        // minHeight (not a fixed height) reserves the same space when
        // there's no error, but lets a longer message — these can carry
        // a full exception detail, not just a short phrase — wrap to a
        // second line instead of being silently clipped.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: widget.state.errorMessage != null
              ? Text(widget.state.errorMessage!, style: AppTextStyles.danger(AppTextStyles.bodySm), textAlign: TextAlign.center)
              : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Send link',
          loading: sending,
          onPressed: widget.state.email.trim().isEmpty ? null : widget.controller.sendLink,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextButton(
          onPressed: sending ? null : () => Navigator.of(context).maybePop(),
          child: Text('Back to sign in', style: AppTextStyles.secondary(AppTextStyles.bodyMd)),
        ),
      ],
    );
  }
}

class _LinkSent extends StatelessWidget {
  final VerificationState state;
  final VerificationController controller;

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
          'We sent a link to ${state.email}. Open it on THIS device to finish verifying.',
          style: AppTextStyles.secondary(AppTextStyles.bodyMd),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        // Real testing showed this email reliably lands in spam/junk, not
        // the inbox — without this, a first-time staff member just
        // assumes sending silently failed and gives up.
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
        TextButton(
          onPressed: () => controller.start(),
          child: Text('Use a different email', style: AppTextStyles.secondary(AppTextStyles.bodyMd)),
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
        const SizedBox(height: AppSpacing.xxl),
        const CircularProgressIndicator(color: AppColors.accent),
        const SizedBox(height: AppSpacing.lg),
        Text(message, style: AppTextStyles.secondary(AppTextStyles.bodyMd)),
      ],
    );
  }
}

class _PinSetup extends StatelessWidget {
  final VerificationState state;
  final VerificationController controller;

  const _PinSetup({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final confirming = state.stage == VerificationStage.confirmingPin;
    final filled = confirming ? state.confirmPin.length : state.pin.length;

    return Column(
      children: [
        Icon(Icons.password_outlined, size: 48, color: AppColors.accent),
        const SizedBox(height: AppSpacing.lg),
        Text(
          confirming ? 'Confirm your PIN' : 'Choose a 4-digit PIN',
          style: AppTextStyles.headingLg,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'You\'ll use this PIN to sign in on this device from now on — no email needed.',
          style: AppTextStyles.secondary(AppTextStyles.bodyMd),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxl),
        PinDots(filled: filled),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: state.errorMessage != null
              ? Text(state.errorMessage!, style: AppTextStyles.danger(AppTextStyles.bodySm), textAlign: TextAlign.center)
              : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        NumericKeypad(onKeyTap: controller.tapPinKey),
      ],
    );
  }
}
