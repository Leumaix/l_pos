import 'package:flutter_riverpod/flutter_riverpod.dart';

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
