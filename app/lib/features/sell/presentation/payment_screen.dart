import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../../customers/application/customer_providers.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/customer_form_sheet.dart';
import '../application/cart_controller.dart';
import '../application/checkout_controller.dart';
import '../application/pending_credit_customer_provider.dart';
import '../domain/sale.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final void Function(Sale sale) onSaleComplete;
  final VoidCallback onEmptyCart;

  const PaymentScreen({
    super.key,
    required this.onSaleComplete,
    required this.onEmptyCart,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  PaymentMethod? _method;
  String _cashInput = '';
  Customer? _selectedCustomer;
  String _customerSearch = '';
  bool _submitting = false;
  bool _saleCompleted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A one-time hand-off from Customer detail's "Record sale": if set,
    // pre-select Customer Account + that customer so staff don't have to
    // search for them again. Consumed immediately so it can't leak into
    // a later, unrelated sale.
    final pending = ref.read(pendingCreditCustomerProvider);
    if (pending != null) {
      _method = PaymentMethod.customerAccount;
      _selectedCustomer = pending;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pendingCreditCustomerProvider.notifier).state = null;
      });
    }
  }

  int? get _cashGiven => _cashInput.isEmpty ? null : int.tryParse(_cashInput);

  bool _canSubmit(int total) {
    if (_submitting || _method == null) return false;
    switch (_method!) {
      case PaymentMethod.cash:
        return (_cashGiven ?? 0) >= total;
      case PaymentMethod.card:
      case PaymentMethod.transfer:
        return true;
      case PaymentMethod.customerAccount:
        return _selectedCustomer != null;
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final sale = await ref
          .read(checkoutControllerProvider)
          .completeSale(
            method: _method!,
            cashGiven: _cashGiven,
            customer: _selectedCustomer,
          );
      // Set before calling onSaleComplete: completing the sale clears the
      // cart as a side effect, which can trigger a rebuild of this screen
      // (still mounted, mid-navigation) with an empty cart. Without this
      // flag the empty-cart guard below races the real navigation to
      // Receipt and can win, landing back on Sell instead.
      _saleCompleted = true;
      if (mounted) widget.onSaleComplete(sale);
    } catch (e) {
      if (mounted)
        setState(() => _error = 'Could not complete sale. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final total = cart.total;

    if (cart.isEmpty && !_submitting && !_saleCompleted) {
      // An empty cart here means there's nothing to pay for — most often
      // because a sale just completed and cleared it, and this screen is
      // still reachable via back navigation. Bounce back to Sell instead
      // of showing a payment form for nothing, regardless of how staff
      // got here.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onEmptyCart());
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Payment', style: AppTextStyles.headingSm),
      ),
      body: SafeArea(
        top: false,
        // Wide (tablet): a persistent rail (total + the 4 supported
        // methods as a vertical list) beside the selected method's
        // content, keypad included — matches the reference POS layout.
        // Narrow (phone): today's stacked total/method-grid/section
        // layout, completely unchanged.
        child: Breakpoints.isWide(context)
            ? _buildWideBody(total)
            : _buildNarrowBody(total),
      ),
    );
  }

  Widget _buildNarrowBody(int total) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: ResponsiveCenter(
        maxWidth: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    'Total',
                    style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(formatNaira(total), style: AppTextStyles.numericXl),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 1.6,
              children: [
                _MethodTile(
                  icon: Icons.payments_outlined,
                  label: 'Cash',
                  selected: _method == PaymentMethod.cash,
                  onTap: () => setState(() => _method = PaymentMethod.cash),
                ),
                _MethodTile(
                  icon: Icons.credit_card,
                  label: 'Card',
                  selected: _method == PaymentMethod.card,
                  onTap: () => setState(() => _method = PaymentMethod.card),
                ),
                _MethodTile(
                  icon: Icons.swap_horiz,
                  label: 'Transfer',
                  selected: _method == PaymentMethod.transfer,
                  onTap: () => setState(() => _method = PaymentMethod.transfer),
                ),
                _MethodTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Customer Account',
                  selected: _method == PaymentMethod.customerAccount,
                  onTap: () =>
                      setState(() => _method = PaymentMethod.customerAccount),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _selectedMethodContent(total),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTextStyles.danger(AppTextStyles.bodyMd)),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Complete sale',
              loading: _submitting,
              onPressed: _canSubmit(total) ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideBody(int total) {
    return ResponsiveCenter(
      maxWidth: 1100,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: _PaymentMethodRail(
                  total: total,
                  method: _method,
                  onSelect: (m) => setState(() => _method = m),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_method == null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxl),
                        child: Center(
                          child: Text(
                            'Select a payment method',
                            style: AppTextStyles.muted(AppTextStyles.bodyMd),
                          ),
                        ),
                      )
                    else
                      _selectedMethodContent(total),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _error!,
                        style: AppTextStyles.danger(AppTextStyles.bodyMd),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      label: 'Complete sale',
                      loading: _submitting,
                      onPressed: _canSubmit(total) ? _submit : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectedMethodContent(int total) {
    if (_method == PaymentMethod.cash) {
      return _CashSection(
        total: total,
        input: _cashInput,
        onKeyTap: _onCashKey,
      );
    }
    if (_method == PaymentMethod.customerAccount) {
      return _CustomerAccountSection(
        total: total,
        selected: _selectedCustomer,
        search: _customerSearch,
        onSearchChanged: (v) => setState(() => _customerSearch = v),
        onSelect: (c) => setState(() => _selectedCustomer = c),
        onClear: () => setState(() => _selectedCustomer = null),
      );
    }
    if (_method == PaymentMethod.card || _method == PaymentMethod.transfer) {
      return AppCard(
        child: Text(
          'Confirm to charge ${formatNaira(total)} via ${_method == PaymentMethod.card ? 'card' : 'transfer'}.',
          style: AppTextStyles.bodyMd,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _onCashKey(String key) {
    setState(() {
      if (key == 'back') {
        if (_cashInput.isNotEmpty)
          _cashInput = _cashInput.substring(0, _cashInput.length - 1);
        return;
      }
      if (key == '.') return; // cash is whole naira only
      if (_cashInput.length >= 9) return;
      _cashInput += key;
    });
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MethodTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentTintBg : AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? AppColors.accent : AppColors.textSecondary,
                size: 24,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelMd.copyWith(
                  color: selected ? AppColors.accent : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CashSection extends StatelessWidget {
  final int total;
  final String input;
  final ValueChanged<String> onKeyTap;

  const _CashSection({
    required this.total,
    required this.input,
    required this.onKeyTap,
  });

  @override
  Widget build(BuildContext context) {
    final given = input.isEmpty ? 0 : (int.tryParse(input) ?? 0);
    final delta = given - total;
    final hasInput = input.isNotEmpty;

    return Column(
      children: [
        Text(
          input.isEmpty ? formatNaira(0) : formatNaira(given),
          style: AppTextStyles.numericXl,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          !hasInput
              ? 'Enter cash received'
              : (delta >= 0
                    ? 'Change: ${formatNaira(delta)}'
                    : 'Still need ${formatNaira(-delta)}'),
          style: (delta >= 0 ? AppTextStyles.success : AppTextStyles.danger)(
            AppTextStyles.bodyMd,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        NumericKeypad(onKeyTap: onKeyTap),
      ],
    );
  }
}

class _CustomerAccountSection extends ConsumerWidget {
  final int total;
  final Customer? selected;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Customer> onSelect;
  final VoidCallback onClear;

  const _CustomerAccountSection({
    required this.total,
    required this.selected,
    required this.search,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selected != null) {
      final newBalance = selected!.balance + total;
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selected!.name, style: AppTextStyles.labelLg),
                      Text(
                        selected!.phone,
                        style: AppTextStyles.secondary(AppTextStyles.bodySm),
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: onClear, child: const Text('Change')),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current balance',
                  style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                ),
                Text(
                  formatNaira(selected!.balance),
                  style: AppTextStyles.numericSm,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('New balance', style: AppTextStyles.labelMd),
                Text(
                  formatNaira(newBalance),
                  style: AppTextStyles.danger(AppTextStyles.numericSm),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final customersAsync = ref.watch(customersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: onSearchChanged,
          style: AppTextStyles.bodyLg,
          decoration: const InputDecoration(
            hintText: 'Search customer by name or phone',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: () async {
            // Never shows an opening-balance field, regardless of who's
            // signed in — this is specifically for a walk-in with no
            // prior history, mid-sale, on principle (see
            // showCustomerFormSheet's own doc comment).
            final customer = await showCustomerFormSheet(context);
            if (customer != null) onSelect(customer);
          },
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('New customer'),
        ),
        const SizedBox(height: AppSpacing.md),
        customersAsync.when(
          data: (customers) {
            final query = search.trim().toLowerCase();
            final filtered = query.isEmpty
                ? customers
                : customers
                      .where(
                        (c) =>
                            c.name.toLowerCase().contains(query) ||
                            c.phone.contains(query),
                      )
                      .toList();
            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text(
                  'No customers found',
                  style: AppTextStyles.muted(AppTextStyles.bodyMd),
                ),
              );
            }
            return Column(
              children: [
                for (final customer in filtered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _CustomerRow(
                      customer: customer,
                      onTap: () => onSelect(customer),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          ),
          error: (err, _) => Text(
            'Could not load customers',
            style: AppTextStyles.danger(AppTextStyles.bodyMd),
          ),
        ),
      ],
    );
  }
}

class _CustomerRow extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;

  const _CustomerRow({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.name, style: AppTextStyles.labelMd),
                    Text(
                      customer.phone,
                      style: AppTextStyles.secondary(AppTextStyles.bodySm),
                    ),
                  ],
                ),
              ),
              if (customer.balance > 0)
                Text(
                  'Owes ${formatNaira(customer.balance)}',
                  style: AppTextStyles.danger(AppTextStyles.bodySm),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The wide-mode rail: the running total, then the 4 supported methods —
/// exactly [PaymentMethod]'s values, nothing more — as a vertical list
/// instead of narrow's 2x2 grid of [_MethodTile]s.
class _PaymentMethodRail extends StatelessWidget {
  final int total;
  final PaymentMethod? method;
  final ValueChanged<PaymentMethod> onSelect;

  const _PaymentMethodRail({
    required this.total,
    required this.method,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Total', style: AppTextStyles.secondary(AppTextStyles.bodyMd)),
        const SizedBox(height: AppSpacing.xs),
        Text(formatNaira(total), style: AppTextStyles.numericXl),
        const SizedBox(height: AppSpacing.xl),
        _MethodRow(
          icon: Icons.payments_outlined,
          label: 'Cash',
          selected: method == PaymentMethod.cash,
          onTap: () => onSelect(PaymentMethod.cash),
        ),
        _MethodRow(
          icon: Icons.credit_card,
          label: 'Card',
          selected: method == PaymentMethod.card,
          onTap: () => onSelect(PaymentMethod.card),
        ),
        _MethodRow(
          icon: Icons.swap_horiz,
          label: 'Transfer',
          selected: method == PaymentMethod.transfer,
          onTap: () => onSelect(PaymentMethod.transfer),
        ),
        _MethodRow(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Customer Account',
          selected: method == PaymentMethod.customerAccount,
          onTap: () => onSelect(PaymentMethod.customerAccount),
        ),
      ],
    );
  }
}

class _MethodRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MethodRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: selected ? AppColors.accentTintBg : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Container(
            height: AppSpacing.minTouchTarget + 8,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  label,
                  style: AppTextStyles.labelMd.copyWith(
                    color: selected ? AppColors.accent : AppColors.textPrimary,
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
