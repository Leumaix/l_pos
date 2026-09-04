import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../auth/application/auth_providers.dart';
import '../application/customer_providers.dart';
import '../domain/customer.dart';
import '../domain/customer_totals.dart';
import 'customer_form_sheet.dart';

enum _CustomerFilter { all, owing, cleared }

class CustomersScreen extends ConsumerStatefulWidget {
  final void Function(Customer customer) onOpenCustomer;

  const CustomersScreen({super.key, required this.onOpenCustomer});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _search = '';
  _CustomerFilter _filter = _CustomerFilter.all;

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);
    final isOwner = ref.watch(authStateProvider).valueOrNull?.role == 'owner';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Customers', style: AppTextStyles.headingSm),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_outlined, color: AppColors.textPrimary),
            tooltip: 'Add customer',
            // Only an owner sees the opening-balance field — for
            // migrating an existing debtor's balance from elsewhere
            // (e.g. Odoo). Any staff member can still add a walk-in at
            // the default zero balance from here.
            onPressed: () => showCustomerFormSheet(context, showOpeningBalanceField: isOwner),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: customersAsync.when(
          data: (customers) => _Body(
            customers: customers,
            search: _search,
            filter: _filter,
            onSearchChanged: (v) => setState(() => _search = v),
            onFilterChanged: (f) => setState(() => _filter = f),
            onOpenCustomer: widget.onOpenCustomer,
          ),
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          error: (err, _) => Center(
            child: Text('Could not load customers', style: AppTextStyles.danger(AppTextStyles.bodyMd)),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final List<Customer> customers;
  final String search;
  final _CustomerFilter filter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_CustomerFilter> onFilterChanged;
  final void Function(Customer customer) onOpenCustomer;

  const _Body({
    required this.customers,
    required this.search,
    required this.filter,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onOpenCustomer,
  });

  @override
  Widget build(BuildContext context) {
    final query = search.trim().toLowerCase();
    final filtered = customers.where((c) {
      final matchesSearch =
          query.isEmpty || c.name.toLowerCase().contains(query) || c.phone.contains(query);
      final matchesFilter = switch (filter) {
        _CustomerFilter.all => true,
        _CustomerFilter.owing => c.balance > 0,
        _CustomerFilter.cleared => c.balance <= 0,
      };
      return matchesSearch && matchesFilter;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ResponsiveCenter(
        maxWidth: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total owed', style: AppTextStyles.secondary(AppTextStyles.bodySm)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    formatNaira(totalOwedByCustomers(customers)),
                    style: AppTextStyles.numericXl.copyWith(color: AppColors.danger),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              onChanged: onSearchChanged,
              style: AppTextStyles.bodyLg,
              decoration: const InputDecoration(hintText: 'Search by name or phone'),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: filter == _CustomerFilter.all,
                  onTap: () => onFilterChanged(_CustomerFilter.all),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterChip(
                  label: 'Owing',
                  selected: filter == _CustomerFilter.owing,
                  onTap: () => onFilterChanged(_CustomerFilter.owing),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterChip(
                  label: 'Cleared',
                  selected: filter == _CustomerFilter.cleared,
                  onTap: () => onFilterChanged(_CustomerFilter.cleared),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: Text('No customers found', style: AppTextStyles.muted(AppTextStyles.bodyMd)),
                ),
              )
            else
              for (final customer in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _CustomerRow(customer: customer, onTap: () => onOpenCustomer(customer)),
                ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentTintBg : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        child: Container(
          height: AppSpacing.minTouchTarget - 8,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            border: Border.all(color: selected ? AppColors.accent : AppColors.border),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelSm.copyWith(
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;

  const _CustomerRow({required this.customer, required this.onTap});

  String get _initials {
    final parts = customer.name.trim().split(RegExp(r'\s+'));
    final letters = parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase());
    return letters.join();
  }

  @override
  Widget build(BuildContext context) {
    final owing = customer.balance > 0;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.accentTintBg,
                  shape: BoxShape.circle,
                ),
                child: Text(_initials, style: AppTextStyles.accent(AppTextStyles.labelSm)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.name, style: AppTextStyles.labelMd),
                    Text(customer.phone, style: AppTextStyles.secondary(AppTextStyles.bodySm)),
                  ],
                ),
              ),
              Text(
                owing ? formatNaira(customer.balance) : 'Cleared',
                style: owing
                    ? AppTextStyles.danger(AppTextStyles.numericSm)
                    : AppTextStyles.muted(AppTextStyles.bodySm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
