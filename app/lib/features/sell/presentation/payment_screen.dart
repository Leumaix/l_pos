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
import '../domain/checkout.dart';
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

/// Single-method-by-default, split-by-deliberate-action. The fast path
/// (pick one method, pay, done) is exactly today's flow — no extra taps,
/// nothing new to look at — and falls out of the SAME state/logic a split
/// uses, rather than being a separate code path: with [_committedLines]
/// empty and [_amountEntryRevealed] false, [_remaining] always equals the
/// cart total and [_needsAmountEntry] is only ever true for cash, which is
/// exactly today's behavior. Splitting only begins once staff explicitly
/// reveal an amount field on a non-cash method or commit a line via "Add
/// another payment method" — see [_needsAmountEntry]/[_canAddAnotherMethod].
class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  PaymentMethod? _method;
  String _amountInput = '';
  bool _amountEntryRevealed = false;
  Customer? _selectedCustomer;
  String _customerSearch = '';
  bool _submitting = false;
  bool _saleCompleted = false;
  String? _error;

  /// Lines already committed via "Add another payment method" — empty for
  /// every single-method sale, which is most of them. [_method] is always
  /// the CURRENT, not-yet-committed line being entered.
  final List<PaymentLine> _committedLines = [];

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

  int? get _amountGiven => _amountInput.isEmpty ? null : int.tryParse(_amountInput);

  int get _committedSum => _committedLines.fold(0, (sum, line) => sum + line.amountNaira);

  int _remaining(int total) => total - _committedSum;

  /// True once this line needs its own typed amount rather than
  /// implicitly covering whatever's left: always true for cash (matches
  /// today), true for any method once staff have deliberately revealed
  /// it (see [_revealAmountEntry]), and true unconditionally once a split
  /// is already under way — a second or third line always needs its own
  /// amount, never an implicit "the rest" guess.
  bool get _needsAmountEntry =>
      _method == PaymentMethod.cash || _amountEntryRevealed || _committedLines.isNotEmpty;

  /// The real amount this line covers right now — never capped to
  /// [remaining]: an overpaid line still records the REAL money that
  /// moved (see PaymentLine's own doc comment), with the excess split
  /// into a separate change line at submit time — see [_buildPayments].
  int _activeAmount(int total) => _needsAmountEntry ? (_amountGiven ?? 0) : _remaining(total);

  bool _canSubmit(int total) {
    if (_submitting || _method == null) return false;
    if (_method == PaymentMethod.customerAccount && _selectedCustomer == null) return false;
    return _activeAmount(total) >= _remaining(total);
  }

  /// Whether the CURRENT line, as typed so far, genuinely leaves
  /// something over for another method to cover — the only case "Add
  /// another payment method" makes sense; buildSale's own
  /// kMaxPaymentLines cap is mirrored here too, so the button
  /// disappears before a tap could ever produce a rejected split.
  bool _canAddAnotherMethod(int total) {
    if (_method == null) return false;
    if (_method == PaymentMethod.customerAccount && _selectedCustomer == null) return false;
    if (_committedLines.length + 1 >= kMaxPaymentLines) return false;
    final remaining = _remaining(total);
    final amount = _activeAmount(total);
    return amount > 0 && amount < remaining;
  }

  void _revealAmountEntry() => setState(() => _amountEntryRevealed = true);

  void _addAnotherMethod(int total) {
    setState(() {
      _committedLines.add(
        PaymentLine(
          method: _method!,
          amountNaira: _activeAmount(total),
          customerId: _method == PaymentMethod.customerAccount ? _selectedCustomer?.id : null,
          customerName: _method == PaymentMethod.customerAccount ? _selectedCustomer?.name : null,
        ),
      );
      _method = null;
      _amountInput = '';
      _amountEntryRevealed = false;
      _selectedCustomer = null;
      _customerSearch = '';
      _error = null;
    });
  }

  void _removeCommittedLine(int index) => setState(() => _committedLines.removeAt(index));

  /// The full payments list for the sale as it stands right now —
  /// committed lines, the active line at its real (never-capped) amount,
  /// and — only when the active line overshoots what's left — a separate
  /// negative cash line for the change. Mirrors exactly how a pre-split
  /// cash-with-change sale was already represented, generalized to any
  /// method: buildSale is the single source of truth for whether this
  /// list is actually valid, this method's only job is to construct one.
  List<PaymentLine> _buildPayments(int total) {
    final remaining = _remaining(total);
    final amount = _activeAmount(total);
    final overpay = amount - remaining;
    return [
      ..._committedLines,
      PaymentLine(
        method: _method!,
        amountNaira: amount,
        customerId: _method == PaymentMethod.customerAccount ? _selectedCustomer?.id : null,
        customerName: _method == PaymentMethod.customerAccount ? _selectedCustomer?.name : null,
      ),
      if (overpay > 0) PaymentLine(method: PaymentMethod.cash, amountNaira: -overpay),
    ];
  }

  Future<void> _submit(int total) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final sale = await ref
          .read(checkoutControllerProvider)
          .completeSale(payments: _buildPayments(total));
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
            ..._splitControls(total),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTextStyles.danger(AppTextStyles.bodyMd)),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Complete sale',
              loading: _submitting,
              onPressed: _canSubmit(total) ? () => _submit(total) : null,
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
                  remaining: _remaining(total),
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
                    ..._splitControls(total),
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
                      onPressed: _canSubmit(total) ? () => _submit(total) : null,
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

  /// The committed-lines summary (if any) plus "Add another payment
  /// method" — shared between narrow and wide layouts, inserted right
  /// after the active method's own content in both.
  List<Widget> _splitControls(int total) {
    final widgets = <Widget>[];
    if (_committedLines.isNotEmpty) {
      widgets.add(const SizedBox(height: AppSpacing.lg));
      widgets.add(
        _SplitSummary(
          lines: _committedLines,
          remaining: _remaining(total),
          onRemove: _removeCommittedLine,
        ),
      );
    }
    if (_canAddAnotherMethod(total)) {
      widgets.add(const SizedBox(height: AppSpacing.md));
      widgets.add(
        OutlinedButton.icon(
          onPressed: () => _addAnotherMethod(total),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add another payment method'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            side: const BorderSide(color: AppColors.accent),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _selectedMethodContent(int total) {
    final remaining = _remaining(total);

    if (_method == PaymentMethod.cash) {
      return _AmountEntrySection(
        remaining: remaining,
        input: _amountInput,
        onKeyTap: _onAmountKey,
      );
    }

    if (_method == PaymentMethod.customerAccount) {
      if (_selectedCustomer == null) {
        return _CustomerAccountSection(
          amount: remaining,
          selected: null,
          search: _customerSearch,
          onSearchChanged: (v) => setState(() => _customerSearch = v),
          onSelect: (c) => setState(() => _selectedCustomer = c),
          onClear: () => setState(() => _selectedCustomer = null),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CustomerAccountSection(
            amount: _activeAmount(total),
            selected: _selectedCustomer,
            search: _customerSearch,
            onSearchChanged: (v) => setState(() => _customerSearch = v),
            onSelect: (c) => setState(() => _selectedCustomer = c),
            onClear: () => setState(() => _selectedCustomer = null),
          ),
          if (!_needsAmountEntry) ...[
            const SizedBox(height: AppSpacing.sm),
            _RevealSplitLink(onTap: _revealAmountEntry),
          ],
          if (_needsAmountEntry) ...[
            const SizedBox(height: AppSpacing.lg),
            _AmountEntrySection(
              remaining: remaining,
              input: _amountInput,
              onKeyTap: _onAmountKey,
            ),
          ],
        ],
      );
    }

    // card / transfer
    if (!_needsAmountEntry) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Text(
              'Confirm to charge ${formatNaira(remaining)} via ${_method == PaymentMethod.card ? 'card' : 'transfer'}.',
              style: AppTextStyles.bodyMd,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _RevealSplitLink(onTap: _revealAmountEntry),
        ],
      );
    }
    return _AmountEntrySection(
      remaining: remaining,
      input: _amountInput,
      onKeyTap: _onAmountKey,
    );
  }

  void _onAmountKey(String key) {
    setState(() {
      if (key == 'back') {
        if (_amountInput.isNotEmpty)
          _amountInput = _amountInput.substring(0, _amountInput.length - 1);
        return;
      }
      if (key == '.') return; // whole naira only
      if (_amountInput.length >= 9) return;
      _amountInput += key;
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

/// A live-feedback amount entry — generalizes the old cash-only section
/// to any method: [remaining] is what THIS line needs to cover (the cart
/// total on a single-method sale, or whatever's left once other lines
/// are already committed), so "Change"/"Still need" reads correctly in
/// both the fast path and mid-split.
class _AmountEntrySection extends StatelessWidget {
  final int remaining;
  final String input;
  final ValueChanged<String> onKeyTap;

  const _AmountEntrySection({
    required this.remaining,
    required this.input,
    required this.onKeyTap,
  });

  @override
  Widget build(BuildContext context) {
    final given = input.isEmpty ? 0 : (int.tryParse(input) ?? 0);
    final delta = given - remaining;
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
              ? 'Enter amount received'
              : (delta >= 0
                    ? (delta == 0 ? 'Balances exactly' : 'Change: ${formatNaira(delta)}')
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

/// The lines already committed to this split, each removable — visible
/// only once staff have actually added a second method.
class _SplitSummary extends StatelessWidget {
  final List<PaymentLine> lines;
  final int remaining;
  final ValueChanged<int> onRemove;

  const _SplitSummary({
    required this.lines,
    required this.remaining,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Already added', style: AppTextStyles.secondary(AppTextStyles.bodySm)),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_lineLabel(lines[i]), style: AppTextStyles.bodyMd),
                  ),
                  Text(formatNaira(lines[i].amountNaira), style: AppTextStyles.numericSm),
                  IconButton(
                    onPressed: () => onRemove(i),
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textSecondary,
                    tooltip: 'Remove',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Remaining', style: AppTextStyles.labelMd),
              Text(formatNaira(remaining), style: AppTextStyles.numericSm.copyWith(color: AppColors.accent)),
            ],
          ),
        ],
      ),
    );
  }

  String _lineLabel(PaymentLine line) {
    final base = switch (line.method) {
      PaymentMethod.cash => 'Cash',
      PaymentMethod.card => 'Card',
      PaymentMethod.transfer => 'Transfer',
      PaymentMethod.customerAccount => line.customerName ?? 'Customer Account',
    };
    return line.method == PaymentMethod.customerAccount ? '$base (account)' : base;
  }
}

class _RevealSplitLink extends StatelessWidget {
  final VoidCallback onTap;

  const _RevealSplitLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onTap,
        child: Text(
          'Split — pay only part with this method',
          style: AppTextStyles.accent(AppTextStyles.bodySm),
        ),
      ),
    );
  }
}

class _CustomerAccountSection extends ConsumerWidget {
  final int amount;
  final Customer? selected;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Customer> onSelect;
  final VoidCallback onClear;

  const _CustomerAccountSection({
    required this.amount,
    required this.selected,
    required this.search,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selected != null) {
      final newBalance = selected!.balance + amount;
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
/// instead of narrow's 2x2 grid of [_MethodTile]s. Shows "Remaining" too,
/// once a split is under way — [remaining] equals [total] until then.
class _PaymentMethodRail extends StatelessWidget {
  final int total;
  final int remaining;
  final PaymentMethod? method;
  final ValueChanged<PaymentMethod> onSelect;

  const _PaymentMethodRail({
    required this.total,
    required this.remaining,
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
        if (remaining != total) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Remaining: ${formatNaira(remaining)}',
            style: AppTextStyles.accent(AppTextStyles.bodyMd),
          ),
        ],
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
