import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../application/invite_staff_controller.dart';
import '../domain/staff_invite.dart';

/// Owner-only: add staff in-app without touching the Firebase console.
/// Writing an invite here is only half the story — see
/// FirebaseAuthRepository's self-provisioning logic in _loadStaffDoc for
/// how a real staff doc actually gets created once the invited person
/// completes their own email-link verification, and firestore.rules for
/// the server-side enforcement (invite existence + exact role match)
/// that this screen's writes are independently checked against.
class InviteStaffScreen extends ConsumerWidget {
  const InviteStaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inviteStaffControllerProvider);
    final controller = ref.read(inviteStaffControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Invite staff'), backgroundColor: AppColors.background),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sends a one-time invite. The person still has to verify their own email on their own device before they can sign in — this just says who\'s allowed to.',
                  style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                ),
                const SizedBox(height: AppSpacing.xl),
                _InviteForm(state: state, controller: controller),
                const SizedBox(height: AppSpacing.xxl),
                Text('Pending invites', style: AppTextStyles.headingSm),
                const SizedBox(height: AppSpacing.md),
                _PendingInvites(state: state, controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InviteForm extends StatefulWidget {
  final InviteStaffState state;
  final InviteStaffController controller;

  const _InviteForm({required this.state, required this.controller});

  @override
  State<_InviteForm> createState() => _InviteFormState();
}

class _InviteFormState extends State<_InviteForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.state.name);
    _emailController = TextEditingController(text: widget.state.email);
  }

  @override
  void didUpdateWidget(covariant _InviteForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only sync when a field is cleared out from under the user (a
    // successful submit resets the form) — never fight their own
    // typing, which already keeps state in step via onChanged.
    if (widget.state.name.isEmpty && _nameController.text.isNotEmpty) {
      _nameController.clear();
    }
    if (widget.state.email.isEmpty && _emailController.text.isNotEmpty) {
      _emailController.clear();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final controller = widget.controller;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Name', style: AppTextStyles.labelMd),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _nameController,
            enabled: !state.submitting,
            onChanged: controller.setName,
            decoration: const InputDecoration(hintText: 'Full name'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Email', style: AppTextStyles.labelMd),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _emailController,
            enabled: !state.submitting,
            keyboardType: TextInputType.emailAddress,
            onChanged: controller.setEmail,
            decoration: const InputDecoration(hintText: 'name@example.com'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Role', style: AppTextStyles.labelMd),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final role in kStaffRoles) ...[
                _RoleChip(
                  role: role,
                  selected: state.role == role,
                  onTap: state.submitting ? null : () => controller.setRole(role),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
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
            label: 'Send invite',
            loading: state.submitting,
            onPressed: state.canSubmit ? controller.submit : null,
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  final bool selected;
  final VoidCallback? onTap;

  const _RoleChip({required this.role, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentTintBg : AppColors.background,
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            border: Border.all(color: selected ? AppColors.accent : AppColors.border),
          ),
          child: Text(
            role[0].toUpperCase() + role.substring(1),
            style: AppTextStyles.labelMd.copyWith(color: selected ? AppColors.accent : AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _PendingInvites extends StatelessWidget {
  final InviteStaffState state;
  final InviteStaffController controller;

  const _PendingInvites({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (state.loadingInvites) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }
    if (state.invites.isEmpty) {
      return AppCard(
        child: Text('No pending invites.', style: AppTextStyles.secondary(AppTextStyles.bodyMd)),
      );
    }
    return Column(
      children: [
        for (final invite in state.invites) ...[
          _PendingInviteTile(invite: invite, onRevoke: () => controller.revoke(invite.email)),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _PendingInviteTile extends StatelessWidget {
  final StaffInvite invite;
  final VoidCallback onRevoke;

  const _PendingInviteTile({required this.invite, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invite.name, style: AppTextStyles.labelLg),
                const SizedBox(height: AppSpacing.xs),
                Text(invite.email, style: AppTextStyles.secondary(AppTextStyles.bodySm)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  invite.role[0].toUpperCase() + invite.role.substring(1),
                  style: AppTextStyles.accent(AppTextStyles.bodySm),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.danger),
            tooltip: 'Revoke invite',
            onPressed: onRevoke,
          ),
        ],
      ),
    );
  }
}
