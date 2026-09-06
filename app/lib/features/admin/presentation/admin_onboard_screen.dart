import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../application/admin_auth_controller.dart';
import '../application/admin_onboarding_controller.dart';

/// The whole tool, in one screen: business ID (slug), display name,
/// owner's name and email. Submit does exactly two writes — see
/// BusinessOnboardingRepository — reusing the mobile app's existing
/// invite/self-provisioning flow for everything after that, unchanged.
class AdminOnboardScreen extends ConsumerWidget {
  const AdminOnboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminOnboardingControllerProvider);
    final controller = ref.read(adminOnboardingControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Onboard a business'),
        backgroundColor: AppColors.background,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(adminAuthControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.justOnboarded != null) ...[
                  _SuccessBanner(businessId: state.justOnboarded!.businessId, ownerEmail: state.justOnboarded!.ownerEmail),
                  const SizedBox(height: AppSpacing.xl),
                ],
                Text(
                  'Creates the business and sends its first owner an invite — the same one-time email-link setup any staff member goes through, just with the owner role.',
                  style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                ),
                const SizedBox(height: AppSpacing.xl),
                _OnboardForm(state: state, controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String businessId;
  final String ownerEmail;

  const _SuccessBanner({required this.businessId, required this.ownerEmail});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.success),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '"$businessId" created — invite sent to $ownerEmail.',
              style: AppTextStyles.success(AppTextStyles.bodyMd),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardForm extends StatefulWidget {
  final AdminOnboardingState state;
  final AdminOnboardingController controller;

  const _OnboardForm({required this.state, required this.controller});

  @override
  State<_OnboardForm> createState() => _OnboardFormState();
}

class _OnboardFormState extends State<_OnboardForm> {
  late final TextEditingController _businessIdController;
  late final TextEditingController _businessNameController;
  late final TextEditingController _ownerNameController;
  late final TextEditingController _ownerEmailController;

  @override
  void initState() {
    super.initState();
    _businessIdController = TextEditingController(text: widget.state.businessId);
    _businessNameController = TextEditingController(text: widget.state.businessName);
    _ownerNameController = TextEditingController(text: widget.state.ownerName);
    _ownerEmailController = TextEditingController(text: widget.state.ownerEmail);
  }

  @override
  void didUpdateWidget(covariant _OnboardForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A successful submit resets the controller's state to blank fields —
    // clear the text controllers to match, same "only sync when cleared
    // out from under the user" convention as every other form in this app.
    if (widget.state.businessId.isEmpty && _businessIdController.text.isNotEmpty) {
      _businessIdController.clear();
    }
    if (widget.state.businessName.isEmpty && _businessNameController.text.isNotEmpty) {
      _businessNameController.clear();
    }
    if (widget.state.ownerName.isEmpty && _ownerNameController.text.isNotEmpty) {
      _ownerNameController.clear();
    }
    if (widget.state.ownerEmail.isEmpty && _ownerEmailController.text.isNotEmpty) {
      _ownerEmailController.clear();
    }
  }

  @override
  void dispose() {
    _businessIdController.dispose();
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _ownerEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final controller = widget.controller;
    final idInvalid = state.businessId.isNotEmpty && !isValidBusinessSlug(state.businessId);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Business ID', style: AppTextStyles.labelMd),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _businessIdController,
            enabled: !state.submitting,
            onChanged: controller.setBusinessId,
            decoration: const InputDecoration(hintText: 'ph-zazaa'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            idInvalid
                ? 'Lowercase letters, digits, and single hyphens only.'
                : 'This becomes a permanent Firestore document id — lowercase letters, digits, and hyphens only.',
            style: idInvalid ? AppTextStyles.danger(AppTextStyles.bodySm) : AppTextStyles.secondary(AppTextStyles.bodySm),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Business display name', style: AppTextStyles.labelMd),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _businessNameController,
            enabled: !state.submitting,
            onChanged: controller.setBusinessName,
            decoration: const InputDecoration(hintText: 'PH-Zazaa Oil & Gas'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Owner\'s full name', style: AppTextStyles.labelMd),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _ownerNameController,
            enabled: !state.submitting,
            onChanged: controller.setOwnerName,
            decoration: const InputDecoration(hintText: 'Full name'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Owner\'s email', style: AppTextStyles.labelMd),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _ownerEmailController,
            enabled: !state.submitting,
            keyboardType: TextInputType.emailAddress,
            onChanged: controller.setOwnerEmail,
            decoration: const InputDecoration(hintText: 'name@example.com'),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 20,
            child: state.errorMessage != null
                ? Text(state.errorMessage!, style: AppTextStyles.danger(AppTextStyles.bodySm))
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Onboard business',
            loading: state.submitting,
            onPressed: state.canSubmit ? controller.submit : null,
          ),
        ],
      ),
    );
  }
}
