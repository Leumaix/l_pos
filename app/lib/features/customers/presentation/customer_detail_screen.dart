import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../sell/application/pending_credit_customer_provider.dart';
import '../application/customer_providers.dart';
import '../domain/customer.dart';
import '../domain/customer_transaction.dart';
import 'repayment_sheet.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final String customerId;
  final VoidCallback onStartCreditSale;

  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    required this.onStartCreditSale,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Customer', style: AppTextStyles.headingSm),
      ),
      body: SafeArea(
        top: false,
        child: customersAsync.when(
          data: (customers) {
            final matches = customers.where((c) => c.id == customerId);
            final customer = matches.isEmpty ? null : matches.first;
            if (customer == null) {
              return Center(
                child: Text('Customer not found', style: AppTextStyles.muted(AppTextStyles.bodyMd)),
              );
            }
            return _Body(customer: customer, onStartCreditSale: onStartCreditSale);
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          error: (err, _) => Center(
            child: Text('Could not load customer', style: AppTextStyles.danger(AppTextStyles.bodyMd)),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final Customer customer;
  final VoidCallback onStartCreditSale;

  const _Body({required this.customer, required this.onStartCreditSale});

  String get _initials {
    final parts = customer.name.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(customerTransactionsProvider(customer.id));
    final owing = customer.balance > 0;
    final credit = customer.balance < 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ResponsiveCenter(
        maxWidth: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.accentTintBg,
                    shape: BoxShape.circle,
                  ),
                  child: Text(_initials, style: AppTextStyles.accent(AppTextStyles.headingSm)),
                ),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.name, style: AppTextStyles.headingSm),
                    Text(customer.phone, style: AppTextStyles.secondary(AppTextStyles.bodyMd)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: owing ? AppColors.dangerBg : (credit ? AppColors.successBg : AppColors.surface),
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                border: owing || credit ? null : Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    credit ? 'Store credit' : 'Balance owed',
                    style: AppTextStyles.secondary(AppTextStyles.bodySm),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    formatNaira(credit ? -customer.balance : customer.balance),
                    style: AppTextStyles.numericXl.copyWith(
                      color: owing
                          ? AppColors.danger
                          : (credit ? AppColors.success : AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // Hand off to Sell → Payment, pre-selected —
                      // a credit sale affects stock like any other sale,
                      // so it goes through the real cart, not a manual
                      // balance bump.
                      ref.read(pendingCreditCustomerProvider.notifier).state = customer;
                      onStartCreditSale();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                      ),
                    ),
                    child: const Text('Record sale'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => showRepaymentSheet(context, customer: customer),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                      ),
                    ),
                    child: const Text('Record payment'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('History', style: AppTextStyles.headingSm),
            const SizedBox(height: AppSpacing.md),
            transactionsAsync.when(
              data: (transactions) {
                if (transactions.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text(
                      'No history yet',
                      style: AppTextStyles.muted(AppTextStyles.bodyMd),
                    ),
                  );
                }
                final ordered = transactions.reversed.toList();
                return Column(
                  children: [
                    for (var i = 0; i < ordered.length; i++)
                      _TransactionRow(transaction: ordered[i], isLast: i == ordered.length - 1),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
              error: (err, _) => Text(
                'Could not load history',
                style: AppTextStyles.danger(AppTextStyles.bodyMd),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final CustomerTransaction transaction;
  final bool isLast;

  const _TransactionRow({required this.transaction, required this.isLast});

  @override
  Widget build(BuildContext context) {
    // creditSale and openingBalance both increase what's owed; only
    // repayment decreases it.
    final isIncrease = transaction.type != CustomerTransactionType.repayment;
    final label = switch (transaction.type) {
      CustomerTransactionType.creditSale => 'Credit sale',
      CustomerTransactionType.repayment => 'Payment',
      CustomerTransactionType.openingBalance => 'Opening balance',
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.bodyLg),
                Text(
                  DateFormat('d MMM yyyy, h:mm a').format(transaction.createdAt),
                  style: AppTextStyles.muted(AppTextStyles.bodySm),
                ),
              ],
            ),
          ),
          Text(
            '${isIncrease ? '+' : '-'}${formatNaira(transaction.amountNaira)}',
            style: (isIncrease ? AppTextStyles.danger : AppTextStyles.success)(AppTextStyles.numericSm),
          ),
        ],
      ),
    );
  }
}
