import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import 'auth_providers.dart';

const _pinLength = 4;

enum LoginSubmitResult { success, failure, needsVerification }

class LoginFormState {
  final String email;
  final String pin;
  final bool submitting;
  final String? errorMessage;

  const LoginFormState({
    this.email = '',
    this.pin = '',
    this.submitting = false,
    this.errorMessage,
  });

  bool get canSubmit => !submitting && email.trim().isNotEmpty && pin.length == _pinLength;

  LoginFormState copyWith({
    String? email,
    String? pin,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LoginFormState(
      email: email ?? this.email,
      pin: pin ?? this.pin,
      submitting: submitting ?? this.submitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class LoginController extends StateNotifier<LoginFormState> {
  final AuthRepository _authRepository;

  LoginController(this._authRepository) : super(const LoginFormState());

  void setEmail(String email) {
    state = state.copyWith(email: email, clearError: true);
  }

  void tapKey(String key) {
    if (state.submitting) return;

    if (key == 'back') {
      if (state.pin.isEmpty) return;
      state = state.copyWith(pin: state.pin.substring(0, state.pin.length - 1), clearError: true);
      return;
    }

    if (state.pin.length >= _pinLength) return;
    state = state.copyWith(pin: state.pin + key, clearError: true);
  }

  Future<LoginSubmitResult> submit() async {
    if (!state.canSubmit) return LoginSubmitResult.failure;

    state = state.copyWith(submitting: true, clearError: true);
    try {
      await _authRepository.signInWithEmailAndPin(email: state.email.trim(), pin: state.pin);
      state = state.copyWith(submitting: false);
      return LoginSubmitResult.success;
    } on DeviceVerificationRequiredException {
      state = state.copyWith(submitting: false, pin: '', clearError: true);
      return LoginSubmitResult.needsVerification;
    } on PinLockedException catch (e) {
      final seconds = e.lockedUntil.difference(DateTime.now()).inSeconds.clamp(1, 999);
      state = state.copyWith(
        submitting: false,
        pin: '',
        errorMessage: 'Too many attempts. Try again in ${seconds}s.',
      );
      return LoginSubmitResult.failure;
    } on InvalidCredentialsException {
      state = state.copyWith(
        submitting: false,
        pin: '',
        errorMessage: 'Incorrect email or PIN',
      );
      return LoginSubmitResult.failure;
    } on StaffRecordNotFoundException {
      state = state.copyWith(
        submitting: false,
        pin: '',
        errorMessage: 'This account no longer has access. Contact the owner.',
      );
      return LoginSubmitResult.failure;
    } catch (_) {
      state = state.copyWith(submitting: false, errorMessage: 'Something went wrong. Try again.');
      return LoginSubmitResult.failure;
    }
  }
}

final loginControllerProvider = StateNotifierProvider.autoDispose<LoginController, LoginFormState>(
  (ref) => LoginController(ref.watch(authRepositoryProvider)),
);
