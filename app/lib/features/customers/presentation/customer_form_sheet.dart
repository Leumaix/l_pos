import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../application/manage_customers_controller.dart';
import '../domain/customer.dart';

/// Adds a brand-new customer on the spot. Returns the created [Customer]
/// on success (null if dismissed without saving) — callers that need to
/// act on it immediately (Payment screen auto-selecting a just-created
/// walk-in into the in-progress sale) read the result rather than
/// re-querying customersProvider.
///
/// [showOpeningBalanceField] controls whether a starting-balance field
/// appears at all — true only from the owner-only Customers screen path
/// (migrating an existing debtor's balance from elsewhere, e.g. Odoo).
/// The Payment screen's inline "new customer mid-sale" path always
/// passes false, regardless of who's signed in: that flow is for a
/// walk-in with no history, never a starting debt, on principle, not
/// just because staff can't set one — an owner mid-sale shouldn't
/// either, since firestore.rules can't (and shouldn't) distinguish
/// "the owner meant to do this from Payment" from any other create.
Future<Customer?> showCustomerFormSheet(
  BuildContext context, {
  bool showOpeningBalanceField = false,
}) {
  return showModalBottomSheet<Customer?>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.cardRadius)),
    ),
    builder: (context) => _CustomerFormSheet(showOpeningBalanceField: showOpeningBalanceField),
  );
}

class _CustomerFormSheet extends ConsumerStatefulWidget {
  final bool showOpeningBalanceField;

  const _CustomerFormSheet({required this.showOpeningBalanceField});

  @override
  ConsumerState<_CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends ConsumerState<_CustomerFormSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _openingBalanceController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final openingBalanceText = _openingBalanceController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _error = 'Enter a phone number.');
      return;
    }
    var openingBalance = 0;
    if (widget.showOpeningBalanceField && openingBalanceText.isNotEmpty) {
      final parsed = int.tryParse(openingBalanceText);
      if (parsed == null || parsed < 0) {
        setState(() => _error = 'Enter a valid opening balance.');
        return;
      }
      openingBalance = parsed;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final customer = await ref
          .read(manageCustomersControllerProvider)
          .createCustomer(name: name, phone: phone, openingBalanceNaira: openingBalance);
      if (mounted) Navigator.of(context).pop(customer);
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Could not save. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add customer', style: AppTextStyles.headingMd),
              const SizedBox(height: AppSpacing.lg),
              Text('Name', style: AppTextStyles.labelMd),
              const SizedBox(height: AppSpacing.xs),
              TextField(controller: _nameController, enabled: !_submitting),
              const SizedBox(height: AppSpacing.md),
              Text('Phone', style: AppTextStyles.labelMd),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _phoneController,
                enabled: !_submitting,
                keyboardType: TextInputType.phone,
              ),
              if (widget.showOpeningBalanceField) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Opening balance (₦) — optional', style: AppTextStyles.labelMd),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'For migrating an existing debtor. Leave blank for a fresh customer starting at ₦0.',
                  style: AppTextStyles.secondary(AppTextStyles.bodySm),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _openingBalanceController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (_error != null) ...[
                Text(_error!, style: AppTextStyles.danger(AppTextStyles.bodySm)),
                const SizedBox(height: AppSpacing.md),
              ],
              AppButton(label: 'Save', loading: _submitting, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
