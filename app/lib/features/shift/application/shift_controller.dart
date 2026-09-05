import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../domain/shift.dart';
import '../data/shift_repository.dart';
import 'shift_providers.dart';

class OpenDayFormState {
  final String floatInput;
  final bool submitting;
  final String? errorMessage;
  final bool justOpened;

  const OpenDayFormState({
    this.floatInput = '',
    this.submitting = false,
    this.errorMessage,
    this.justOpened = false,
  });

  OpenDayFormState copyWith({
    String? floatInput,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
    bool? justOpened,
  }) {
    return OpenDayFormState(
      floatInput: floatInput ?? this.floatInput,
      submitting: submitting ?? this.submitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      justOpened: justOpened ?? this.justOpened,
    );
  }
}

/// Any active staff member — not owner-only. Declares the starting cash
/// float; the day can't be opened again until this one is closed (see
/// ShiftRepository.openDay's doc comment on why that's structural, not
/// just a UI nicety).
class OpenDayController extends StateNotifier<OpenDayFormState> {
  final Ref ref;

  OpenDayController(this.ref) : super(const OpenDayFormState());

  void setFloatInput(String value) {
    state = state.copyWith(floatInput: value, clearError: true, justOpened: false);
  }

  Future<void> openDay() async {
    final parsed = int.tryParse(state.floatInput.trim());
    // >= 0, not > 0 — a zero float is a legitimate real-world starting
    // point (unlike gas rate/tank capacity, which must be positive).
    if (parsed == null || parsed < 0) {
      state = state.copyWith(errorMessage: 'Enter a valid starting float in ₦.', justOpened: false);
      return;
    }
    final staff = ref.read(authStateProvider).valueOrNull;
    if (staff == null) {
      state = state.copyWith(errorMessage: 'Not signed in.', justOpened: false);
      return;
    }

    state = state.copyWith(submitting: true, clearError: true);
    try {
      await ref
          .read(shiftRepositoryProvider)
          .openDay(openingFloatNaira: parsed, staffId: staff.uid, staffName: staff.name);
      state = const OpenDayFormState(justOpened: true);
    } on ShiftAlreadyOpenException {
      state = state.copyWith(submitting: false, errorMessage: 'A shift is already open.');
    } catch (_) {
      state = state.copyWith(submitting: false, errorMessage: 'Could not open the day. Try again.');
    }
  }
}

final openDayControllerProvider = StateNotifierProvider.autoDispose<OpenDayController, OpenDayFormState>(
  (ref) => OpenDayController(ref),
);

/// What a Close Day confirmation dialog needs — computed before writing
/// anything, same "preview, then confirm" shape as Settings' gas-rate
/// change.
class CloseDayPreview {
  final OpenShift shift;
  final int countedCashNaira;
  final int expectedCashNaira;
  final int varianceNaira;

  const CloseDayPreview({
    required this.shift,
    required this.countedCashNaira,
    required this.expectedCashNaira,
    required this.varianceNaira,
  });
}

class CloseDayFormState {
  final String countedCashInput;
  final bool submitting;
  final String? errorMessage;
  final bool justClosed;

  const CloseDayFormState({
    this.countedCashInput = '',
    this.submitting = false,
    this.errorMessage,
    this.justClosed = false,
  });

  CloseDayFormState copyWith({
    String? countedCashInput,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
    bool? justClosed,
  }) {
    return CloseDayFormState(
      countedCashInput: countedCashInput ?? this.countedCashInput,
      submitting: submitting ?? this.submitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      justClosed: justClosed ?? this.justClosed,
    );
  }
}

/// Any active staff member — not owner-only. Counts the actual drawer
/// against what the shift's own running totals say it should hold.
class CloseDayController extends StateNotifier<CloseDayFormState> {
  final Ref ref;

  CloseDayController(this.ref) : super(const CloseDayFormState());

  void setCountedCashInput(String value) {
    state = state.copyWith(countedCashInput: value, clearError: true, justClosed: false);
  }

  /// Validates the input and returns what a confirmation dialog needs to
  /// show, WITHOUT writing anything yet. Returns null (and sets an
  /// error) for an invalid amount or if no shift is open.
  ///
  /// Deliberately async, via fetchCurrentShift's one-shot authoritative
  /// read — NOT ShiftRepository's cached currentShift getter (what the
  /// router's redirect uses). That getter can still be showing its
  /// cold-start default (null) the very first time it's ever accessed in
  /// a session — e.g. reaching Close Day directly from Home without ever
  /// visiting Sell first — which would falsely report "No shift is
  /// currently open" even though one plainly is.
  Future<CloseDayPreview?> preparePreview() async {
    final parsed = int.tryParse(state.countedCashInput.trim());
    if (parsed == null || parsed < 0) {
      state = state.copyWith(errorMessage: 'Enter a valid counted amount in ₦.', justClosed: false);
      return null;
    }
    final shift = await ref.read(shiftRepositoryProvider).fetchCurrentShift();
    if (shift == null) {
      state = state.copyWith(errorMessage: 'No shift is currently open.', justClosed: false);
      return null;
    }
    final expected = shift.expectedCashNaira;
    return CloseDayPreview(
      shift: shift,
      countedCashNaira: parsed,
      expectedCashNaira: expected,
      varianceNaira: parsed - expected,
    );
  }

  /// Actually commits the close — only ever called after the confirming
  /// staff member has seen the [CloseDayPreview] a dialog showed them.
  Future<void> confirmClose(CloseDayPreview preview) async {
    final staff = ref.read(authStateProvider).valueOrNull;
    if (staff == null) {
      state = state.copyWith(errorMessage: 'Not signed in.', justClosed: false);
      return;
    }

    state = state.copyWith(submitting: true, clearError: true);
    try {
      await ref.read(shiftRepositoryProvider).closeDay(
        countedCashNaira: preview.countedCashNaira,
        staffId: staff.uid,
        staffName: staff.name,
      );
      state = const CloseDayFormState(justClosed: true);
    } on NoShiftOpenException {
      state = state.copyWith(submitting: false, errorMessage: 'No shift is currently open.');
    } catch (_) {
      state = state.copyWith(submitting: false, errorMessage: 'Could not close the day. Try again.');
    }
  }
}

final closeDayControllerProvider = StateNotifierProvider.autoDispose<CloseDayController, CloseDayFormState>(
  (ref) => CloseDayController(ref),
);
