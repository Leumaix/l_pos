import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/stat_card.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/verification_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../business/application/business_providers.dart';
import '../application/dashboard_providers.dart';

class HomeScreen extends ConsumerWidget {
  final VoidCallback onSell;
  final VoidCallback onCustomers;
  final VoidCallback onStock;
  final VoidCallback onReports;

  const HomeScreen({
    super.key,
    required this.onSell,
    required this.onCustomers,
    required this.onStock,
    required this.onReports,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final isOwner = user?.role == 'owner';
    final businessName = ref.watch(businessNameProvider);
    final summary = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      businessName,
                      style: AppTextStyles.secondary(AppTextStyles.labelMd),
                    ),
                    _AccountButton(user: user),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Good day,',
                  style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(user?.name ?? '—', style: AppTextStyles.headingLg),
                const SizedBox(height: AppSpacing.xl),
                summary.when(
                  data: (data) => _DashboardBody(
                    isOwner: isOwner,
                    todaysSalesTotalNaira: data.todaysSalesTotalNaira,
                    gasRemainingKg: data.gasRemainingKg,
                    amountOwedNaira: data.amountOwedByCustomersNaira,
                    onSell: onSell,
                    onCustomers: onCustomers,
                    onStock: onStock,
                    onReports: onReports,
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xxl),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                  ),
                  error: (err, _) => Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxl),
                    child: Text(
                      'Could not load dashboard',
                      style: AppTextStyles.danger(AppTextStyles.bodyMd),
                    ),
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

/// The only place a shift starts or ends: sign out (so the router lands
/// everyone back on Login), or start a second staff member's one-time
/// device verification without disturbing this session — see
/// FirebaseAuthRepository's doc comment on why setPinForVerifiedDevice
/// won't auto-switch the active session on its own.
class _AccountButton extends ConsumerWidget {
  final AppUser? user;

  const _AccountButton({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = user?.role == 'owner';
    return IconButton(
      icon: const Icon(
        Icons.account_circle_outlined,
        color: AppColors.textSecondary,
      ),
      tooltip: 'Account',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.lg,
              horizontal: AppSpacing.xl,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Signed in as',
                    style: AppTextStyles.secondary(AppTextStyles.bodySm),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(user?.name ?? '—', style: AppTextStyles.headingSm),
                  const SizedBox(height: AppSpacing.xl),
                  if (isOwner) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.mail_outline,
                        color: AppColors.textPrimary,
                      ),
                      title: const Text('Invite staff'),
                      subtitle: const Text(
                        'Add staff without the Firebase console',
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        context.push('/invite-staff');
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.category_outlined,
                        color: AppColors.textPrimary,
                      ),
                      title: const Text('Manage Catalog'),
                      subtitle: const Text(
                        'Categories and products for Sell, Stock, Restock',
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        context.push('/manage-catalog');
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.settings_outlined,
                        color: AppColors.textPrimary,
                      ),
                      title: const Text('Settings'),
                      subtitle: const Text('Gas tank capacity'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        context.push('/settings');
                      },
                    ),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.person_add_alt_outlined,
                      color: AppColors.textPrimary,
                    ),
                    title: const Text('Verify another staff member'),
                    subtitle: const Text(
                      'Sets up a new PIN without ending your shift',
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref.read(verificationControllerProvider.notifier).start();
                      context.push('/verify-email');
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.logout, color: AppColors.danger),
                    title: const Text('Sign out'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref.read(authRepositoryProvider).signOut();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final bool isOwner;
  final int todaysSalesTotalNaira;
  final double gasRemainingKg;
  final int amountOwedNaira;
  final VoidCallback onSell;
  final VoidCallback onCustomers;
  final VoidCallback onStock;
  final VoidCallback onReports;

  const _DashboardBody({
    required this.isOwner,
    required this.todaysSalesTotalNaira,
    required this.gasRemainingKg,
    required this.amountOwedNaira,
    required this.onSell,
    required this.onCustomers,
    required this.onStock,
    required this.onReports,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Revenue and debt are business-wide financial figures — an
        // attendant only needs what's on the shelf right now to do their
        // job, never how much the business made or is owed.
        if (isOwner) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's sales",
                  style: AppTextStyles.secondary(AppTextStyles.bodySm),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  formatNaira(todaysSalesTotalNaira),
                  style: AppTextStyles.numericXl,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Gas remaining',
                  value: formatKg(gasRemainingKg),
                  icon: Icons.local_fire_department_outlined,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  label: 'Amount owed',
                  value: formatNaira(amountOwedNaira),
                  valueColor: amountOwedNaira > 0 ? AppColors.danger : null,
                  icon: Icons.people_outline,
                ),
              ),
            ],
          ),
        ] else
          StatCard(
            label: 'Gas remaining',
            value: formatKg(gasRemainingKg),
            icon: Icons.local_fire_department_outlined,
          ),
        const SizedBox(height: AppSpacing.xl),
        Text('Quick actions', style: AppTextStyles.headingSm),
        const SizedBox(height: AppSpacing.md),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.5,
          children: [
            _QuickAction(
              icon: Icons.point_of_sale,
              label: 'Sell',
              onTap: onSell,
            ),
            _QuickAction(
              icon: Icons.people_alt_outlined,
              label: 'Customers',
              onTap: onCustomers,
            ),
            // Stock and Reports expose business-wide inventory value and
            // sales history — owner-only, same boundary as the account
            // menu's Manage Catalog/Settings. Enforced for real by the
            // router's redirect (see app_router.dart), not just by
            // leaving the tile off here.
            if (isOwner) ...[
              _QuickAction(
                icon: Icons.inventory_2_outlined,
                label: 'Stock',
                onTap: onStock,
              ),
              _QuickAction(
                icon: Icons.bar_chart_outlined,
                label: 'Reports',
                onTap: onReports,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.accent, size: 26),
              const SizedBox(height: AppSpacing.sm),
              Text(label, style: AppTextStyles.labelMd),
            ],
          ),
        ),
      ),
    );
  }
}
