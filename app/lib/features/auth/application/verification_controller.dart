import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import 'auth_providers.dart';

enum VerificationStage {
  /// Entering/confirming which email to send a link to.
  form,
  sending,

  /// Link sent — waiting for the staff member to open it on this device.
  linkSent,

  /// The deep link arrived; completing the real Firebase sign-in.
  completingLink,

  /// Signed in via the link — now choosing a PIN for daily use.
  choosingPin,

  /// Re-entering the PIN to confirm it before it's stored.
  confirmingPin,
  settingPin,
  done,

  /// Email ownership was proven but there's no active staff record for
  /// it — a stranger, or a deactivated former staff member.
  notAuthorized,

  /// PIN was set successfully, but another staff member is already
  /// signed in on this shared device, so this session wasn't activated.
  awaitingHandoff,
}

class VerificationState {
  final VerificationStage stage;
  final String email;
  final String pin;
  final String confirmPin;
  final String? errorMessage;

  /// Set only in [VerificationStage.awaitingHandoff]: the name of whoever
  /// is currently signed in on this device, for a "ask them to sign out"
  /// message.
  final String? blockingUserName;

  const VerificationState({
    this.stage = VerificationStage.form,
    this.email = '',
    this.pin = '',
    this.confirmPin = '',
    this.errorMessage,
    this.blockingUserName,
  });

  VerificationState copyWith({
    VerificationStage? stage,
    String? email,
    String? pin,
    String? confirmPin,
    String? errorMessage,
    bool clearError = false,
    String? blockingUserName,
  }) {
    return VerificationState(
      stage: stage ?? this.stage,
      email: email ?? this.email,
      pin: pin ?? this.pin,
      confirmPin: confirmPin ?? this.confirmPin,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      blockingUserName: blockingUserName ?? this.blockingUserName,
    );
  }
}

class VerificationController extends StateNotifier<VerificationState> {
  final AuthRepository _authRepository;

  VerificationController(this._authRepository) : super(const VerificationState());

  void start({String? prefillEmail}) {
    state = VerificationState(email: prefillEmail ?? '');
  }

  void setEmail(String email) {
    state = state.copyWith(email: email, clearError: true);
  }

  Future<void> sendLink() async {
    final email = state.email.trim();
    if (email.isEmpty) return;

    state = state.copyWith(stage: VerificationStage.sending, clearError: true);
    try {
      await _authRepository.sendVerificationLink(email);
      state = state.copyWith(stage: VerificationStage.linkSent);
    } catch (e, st) {
      // Was a bare 'Check the email and try again.' with the real
      // exception thrown away — made a real send failure (wrong Firebase
      // config, disabled provider, unauthorized domain, ...) look like a
      // typo in the email. Surface the actual error until this is
      // understood; revisit once it's a known, expected failure mode.
      debugPrint('sendVerificationLink failed: ${e.runtimeType}: $e\n$st');
      state = state.copyWith(
        stage: VerificationStage.form,
        errorMessage: 'Could not send the link — ${e.runtimeType}: $e',
      );
    }
  }

  /// Called by the app-level deep-link listener when the email link is
  /// opened. Looks up which email is pending (survives a cold start
  /// between sending the link and tapping it) rather than trusting
  /// whatever email happens to be in [state] right now.
  Future<void> handleIncomingLink(String link) async {
    final pendingEmail = await _authRepository.pendingVerificationEmail();
    if (pendingEmail == null) {
      state = state.copyWith(
        errorMessage: 'This link doesn\'t match a pending verification on this device.',
      );
      return;
    }

    state = VerificationState(stage: VerificationStage.completingLink, email: pendingEmail);
    try {
      await _authRepository.completeEmailLinkSignIn(email: pendingEmail, emailLink: link);
      state = state.copyWith(stage: VerificationStage.choosingPin);
    } on StaffRecordNotFoundException {
      state = state.copyWith(stage: VerificationStage.notAuthorized, clearError: true);
    } catch (e, st) {
      debugPrint('completeEmailLinkSignIn failed: ${e.runtimeType}: $e\n$st');
      state = state.copyWith(
        stage: VerificationStage.form,
        errorMessage: 'That link is invalid or expired — ${e.runtimeType}: $e',
      );
    }
  }

  void tapPinKey(String key) {
    final isConfirming = state.stage == VerificationStage.confirmingPin;
    final current = isConfirming ? state.confirmPin : state.pin;

    if (key == 'back') {
      if (current.isEmpty) return;
      final updated = current.substring(0, current.length - 1);
      state = isConfirming ? state.copyWith(confirmPin: updated, clearError: true) : state.copyWith(pin: updated, clearError: true);
      return;
    }

    if (current.length >= 4) return;
    final updated = current + key;

    if (!isConfirming) {
      state = state.copyWith(pin: updated, clearError: true);
      if (updated.length == 4) {
        state = state.copyWith(stage: VerificationStage.confirmingPin);
      }
      return;
    }

    state = state.copyWith(confirmPin: updated, clearError: true);
    if (updated.length == 4) {
      _finishChoosingPin();
    }
  }

  Future<void> _finishChoosingPin() async {
    if (state.pin != state.confirmPin) {
      state = state.copyWith(
        stage: VerificationStage.choosingPin,
        pin: '',
        confirmPin: '',
        errorMessage: 'PINs didn\'t match — try again.',
      );
      return;
    }

    state = state.copyWith(stage: VerificationStage.settingPin, clearError: true);
    try {
      final result = await _authRepository.setPinForVerifiedDevice(email: state.email, pin: state.pin);
      state = state.copyWith(
        stage: result.activated ? VerificationStage.done : VerificationStage.awaitingHandoff,
        blockingUserName: result.currentActiveUser?.name,
      );
    } on StaffRecordNotFoundException {
      state = state.copyWith(stage: VerificationStage.notAuthorized, clearError: true);
    } catch (e, st) {
      debugPrint('setPinForVerifiedDevice failed: ${e.runtimeType}: $e\n$st');
      state = state.copyWith(
        stage: VerificationStage.choosingPin,
        pin: '',
        confirmPin: '',
        errorMessage: 'Could not save the PIN. Try again.',
      );
    }
  }
}

final verificationControllerProvider = StateNotifierProvider<VerificationController, VerificationState>(
  (ref) => VerificationController(ref.watch(authRepositoryProvider)),
);
