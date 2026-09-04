import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_button.dart';
import '../../business/application/business_providers.dart';
import '../application/last_sale_provider.dart';
import '../domain/cart_line.dart';
import '../domain/receipt_text.dart';
import '../domain/sale.dart';

class ReceiptScreen extends ConsumerWidget {
  final VoidCallback onNewSale;

  const ReceiptScreen({super.key, required this.onNewSale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sale = ref.watch(lastSaleProvider);
    final businessName = ref.watch(businessNameProvider);

    if (sale == null) {
      // Reached directly (e.g. a page reload) with nothing to show —
      // there's no sale to render a receipt for, so send staff back to
      // a working screen instead of a blank one.
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No sale to show', style: AppTextStyles.secondary(AppTextStyles.bodyMd)),
              const SizedBox(height: AppSpacing.lg),
              AppButton(label: 'Back to Sell', onPressed: onNewSale),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 480,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xl),
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.successBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: AppColors.success, size: 36),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Sale complete', style: AppTextStyles.headingLg),
                const SizedBox(height: AppSpacing.xxl),
                _ReceiptCard(sale: sale, businessName: businessName),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _share(sale, businessName),
                        icon: const Icon(Icons.ios_share, size: 18),
                        label: const Text('Share'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: AppButton(label: 'New sale', onPressed: onNewSale)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _share(Sale sale, String businessName) {
    final text = formatReceiptText(sale, businessName: businessName);
    Share.share(text, subject: 'Receipt ${sale.receiptNumber}');
  }
}

class _ReceiptCard extends StatelessWidget {
  final Sale sale;
  final String businessName;

  const _ReceiptCard({required this.sale, required this.businessName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Text(businessName, style: AppTextStyles.headingSm)),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              'Receipt #${sale.receiptNumber}',
              style: AppTextStyles.muted(AppTextStyles.bodySm),
            ),
          ),
          Center(
            child: Text(
              DateFormat('d MMM yyyy, h:mm a').format(sale.createdAt),
              style: AppTextStyles.muted(AppTextStyles.bodySm),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _DashedDivider(),
          const SizedBox(height: AppSpacing.md),
          for (final line in sale.items) _ReceiptLineRow(line: line),
          const SizedBox(height: AppSpacing.md),
          const _DashedDivider(),
          const SizedBox(height: AppSpacing.md),
          _AmountRow(label: 'Subtotal', value: sale.subtotal),
          const SizedBox(height: AppSpacing.xs),
          _AmountRow(label: 'Total', value: sale.total, emphasize: true),
          const SizedBox(height: AppSpacing.md),
          const _DashedDivider(),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(label: 'Payment', value: _paymentMethodLabel(sale.method)),
          if (sale.method == PaymentMethod.cash) ...[
            _AmountRow(label: 'Cash received', value: sale.cashGiven ?? 0),
            _AmountRow(label: 'Change', value: sale.changeGiven ?? 0, emphasize: true, success: true),
          ],
          if (sale.method == PaymentMethod.customerAccount)
            _InfoRow(label: 'Charged to', value: sale.customerName ?? ''),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(label: 'Served by', value: sale.staffName),
        ],
      ),
    );
  }
}

String _paymentMethodLabel(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => 'Cash',
  PaymentMethod.card => 'Card',
  PaymentMethod.transfer => 'Transfer',
  PaymentMethod.customerAccount => 'Customer Account',
};

class _ReceiptLineRow extends StatelessWidget {
  final CartLine line;

  const _ReceiptLineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final qty = line is ProductCartLine ? (line as ProductCartLine).quantity : 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              qty > 1 ? '${line.name} x$qty' : line.name,
              style: AppTextStyles.bodyMd,
            ),
          ),
          Text(formatNaira(line.lineTotal), style: AppTextStyles.numericSm),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final int value;
  final bool emphasize;
  final bool success;

  const _AmountRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.success = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = emphasize ? AppTextStyles.numericMd : AppTextStyles.numericSm;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: emphasize ? AppTextStyles.labelMd : AppTextStyles.secondary(AppTextStyles.bodyMd),
          ),
          Text(
            formatNaira(value),
            style: success ? valueStyle.copyWith(color: AppColors.success) : valueStyle,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.secondary(AppTextStyles.bodyMd)),
          Text(value, style: AppTextStyles.bodyMd),
        ],
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 6.0;
        const dashGap = 4.0;
        final count = (constraints.maxWidth / (dashWidth + dashGap)).floor();
        return SizedBox(
          height: 1,
          child: Row(
            children: List.generate(
              count,
              (_) => Container(width: dashWidth, height: 1, color: AppColors.border),
            ).expand((w) => [w, const SizedBox(width: dashGap)]).toList(),
          ),
        );
      },
    );
  }
}
