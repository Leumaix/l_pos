import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gas_stock/gas_stock.dart';

import '../../auth/application/auth_providers.dart';
import '../../sell/application/inventory_providers.dart';
import '../data/business_repository.dart';
import 'business_providers.dart';

class SettingsFormState {
  final String capacityInput;
  final bool submitting;
  final String? errorMessage;
  final bool justSaved;

  const SettingsFormState({
    this.capacityInput = '',
    this.submitting = false,
    this.errorMessage,
    this.justSaved = false,
  });

  SettingsFormState copyWith({
    String? capacityInput,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
    bool? justSaved,
  }) {
    return SettingsFormState(
      capacityInput: capacityInput ?? this.capacityInput,
      submitting: submitting ?? this.submitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      justSaved: justSaved ?? this.justSaved,
    );
  }
}

class SettingsController extends StateNotifier<SettingsFormState> {
  final BusinessRepository _repository;

  SettingsController(this._repository) : super(const SettingsFormState());

  void setCapacityInput(String value) {
    state = state.copyWith(capacityInput: value, clearError: true, justSaved: false);
  }

  Future<void> saveGasTankCapacity() async {
    final parsed = double.tryParse(state.capacityInput.trim());
    if (parsed == null || parsed <= 0) {
      state = state.copyWith(errorMessage: 'Enter a valid capacity in kg.', justSaved: false);
      return;
    }

    state = state.copyWith(submitting: true, clearError: true);
    try {
      await _repository.updateGasTankCapacityKg(parsed);
      state = const SettingsFormState(justSaved: true);
    } catch (_) {
      state = state.copyWith(submitting: false, errorMessage: 'Could not save. Try again.');
    }
  }
}

final settingsControllerProvider = StateNotifierProvider.autoDispose<SettingsController, SettingsFormState>(
  (ref) => SettingsController(ref.watch(businessRepositoryProvider)),
);

class GasRatePreview {
  final GasRate oldRate;
  final GasRate newRate;
  final double preservedKg;

  const GasRatePreview({required this.oldRate, required this.newRate, required this.preservedKg});
}

class GasRateFormState {
  final String rateInput;
  final bool submitting;
  final String? errorMessage;
  final bool justSaved;

  const GasRateFormState({
    this.rateInput = '',
    this.submitting = false,
    this.errorMessage,
    this.justSaved = false,
  });

  GasRateFormState copyWith({
    String? rateInput,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
    bool? justSaved,
  }) {
    return GasRateFormState(
      rateInput: rateInput ?? this.rateInput,
      submitting: submitting ?? this.submitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      justSaved: justSaved ?? this.justSaved,
    );
  }
}

/// Owner-only. Deliberately separate from [SettingsController]: this one
/// needs InventoryRepository (gasRate/currentGasStock/changeGasRate) and
/// the signed-in staff member (to attribute the ledger entry), not
/// BusinessRepository — same "Ref, not a single injected repository"
/// shape as RestockController, since it spans two providers.
class GasRateController extends StateNotifier<GasRateFormState> {
  final Ref ref;

  GasRateController(this.ref) : super(const GasRateFormState());

  void setRateInput(String value) {
    state = state.copyWith(rateInput: value, clearError: true, justSaved: false);
  }

  /// Validates the input and returns what a confirmation dialog needs to
  /// show — the old rate, the new rate, and the physical kg the change
  /// will preserve — WITHOUT writing anything yet. Returns null (and sets
  /// an error) for a non-positive/unparseable rate. Synchronous: reads
  /// InventoryRepository's cached gasRate/currentGasStock, same contract
  /// RestockController relies on.
  GasRatePreview? preparePreview() {
    final parsed = int.tryParse(state.rateInput.trim());
    if (parsed == null || parsed <= 0) {
      state = state.copyWith(errorMessage: 'Enter a valid rate in ₦/kg.', justSaved: false);
      return null;
    }
    final inventory = ref.read(inventoryRepositoryProvider);
    final oldRate = inventory.gasRate;
    final preservedKg = kgRemaining(inventory.currentGasStock, oldRate);
    return GasRatePreview(oldRate: oldRate, newRate: GasRate(parsed), preservedKg: preservedKg);
  }

  /// Actually commits the rate change — only ever called after the owner
  /// has confirmed the [GasRatePreview] a dialog showed them.
  Future<void> confirmRateChange(GasRate newRate) async {
    final staff = ref.read(authStateProvider).valueOrNull;
    if (staff == null) {
      state = state.copyWith(errorMessage: 'Not signed in.', justSaved: false);
      return;
    }
    state = state.copyWith(submitting: true, clearError: true);
    try {
      await ref
          .read(inventoryRepositoryProvider)
          .changeGasRate(newRate, staffId: staff.uid, staffName: staff.name);
      state = const GasRateFormState(justSaved: true);
    } catch (_) {
      state = state.copyWith(submitting: false, errorMessage: 'Could not save. Try again.');
    }
  }
}

final gasRateControllerProvider = StateNotifierProvider.autoDispose<GasRateController, GasRateFormState>(
  (ref) => GasRateController(ref),
);
