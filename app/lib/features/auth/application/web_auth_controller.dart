import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/web_auth_repository.dart';

enum WebAuthStage {
  /// Entering email + password — either signing in or creating an
  /// account, toggled via [WebAuthState.isSignUpMode].
  form,
  submitting,

  /// Account created, one-time verification email sent — waiting for
  /// the staff member to click it (in any tab/device; Firebase tracks
  /// this server-side, not tied to this browser).
  awaitingVerification,

  /// Verification confirmed; finishing self-provisioning.
  completingSignUp,

  /// Signed in — nothing further needed.
  done,
}

class WebAuthState {
  final WebAuthStage stage;
  final bool isSignUpMode;
  final String email;
  final String password;
  final String? errorMessage;

  const WebAuthState({
    this.stage = WebAuthStage.form,
    this.isSignUpMode = false,
    this.email = '',
    this.password = '',
    this.errorMessage,
  });

  WebAuthState copyWith({
    WebAuthStage? stage,
    bool? isSignUpMode,
    String? email,
    String? password,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WebAuthState(
      stage: stage ?? this.stage,
      isSignUpMode: isSignUpMode ?? this.isSignUpMode,
      email: email ?? this.email,
      password: password ?? this.password,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Email+password sign-up/login for the web/PWA build. Deliberately
/// depends on WebAuthRepository at its CONCRETE type, not the abstract
/// AuthRepository — none of what's called below (signUp, completeSignUp,
/// signIn, resendVerificationEmail, pendingSignUpUser) is on that shared
/// interface, since no other consumer of it (the router, the other
/// Firebase-backed repositories) needs any of it; this controller is
/// inherently web-only and will never need swapping to a different
/// AuthRepository implementation.
class WebAuthController extends StateNotifier<WebAuthState> {
  final WebAuthRepository _repository;

  WebAuthController(this._repository) : super(const WebAuthState()) {
    _resumeSession();
  }

  /// Resumes the right screen after a page reload — including a genuine
  /// browser close-and-reopen days later — rather than losing progress
  /// back to a blank form. Deliberately NOT a synchronous check on
  /// [WebAuthRepository.currentUser] alone: that field lives only in
  /// this (brand-new, on every app boot) repository instance's memory,
  /// so it's always null right after a real reload even when Firebase's
  /// OWN session survived it (that's the actual persistence guarantee —
  /// see WebAuthRepository's own doc comment on Persistence.LOCAL).
  /// [pendingSignUpUser] is the real signal of a surviving Firebase
  /// session; completeSignUp() re-derives a full AppUser from it (reload
  /// + emailVerified check + the same staff-doc lookup signIn uses) —
  /// reused here as the resume path, not just the sign-up path, so a
  /// verified, already-provisioned account lands straight on done rather
  /// than being shown "check your email" again.
  Future<void> _resumeSession() async {
    if (_repository.currentUser != null) {
      state = state.copyWith(stage: WebAuthStage.done);
      return;
    }
    final pending = _repository.pendingSignUpUser;
    if (pending == null) return;
    // So "Check your email" can name the right address if this resume
    // lands on awaitingVerification below — otherwise state.email is
    // whatever it started as (empty), since the form was never visited
    // this session.
    state = state.copyWith(email: pending.email ?? '', stage: WebAuthStage.completingSignUp);
    try {
      await _repository.completeSignUp();
      state = state.copyWith(stage: WebAuthStage.done);
    } on EmailNotVerifiedException {
      state = state.copyWith(stage: WebAuthStage.awaitingVerification, clearError: true);
    } catch (_) {
      // Something genuinely wrong with this session (staff record
      // deactivated since, etc.) — don't trap them on a resume that can
      // never succeed; back to a clean form.
      state = const WebAuthState();
    }
  }

  void setEmail(String email) => state = state.copyWith(email: email, clearError: true);

  void setPassword(String password) => state = state.copyWith(password: password, clearError: true);

  void toggleSignUpMode() =>
      state = state.copyWith(isSignUpMode: !state.isSignUpMode, password: '', clearError: true);

  Future<void> signIn() async {
    final email = state.email.trim();
    final password = state.password;
    if (email.isEmpty || password.isEmpty) return;

    state = state.copyWith(stage: WebAuthStage.submitting, clearError: true);
    try {
      await _repository.signIn(email: email, password: password);
      state = state.copyWith(stage: WebAuthStage.done);
    } catch (e) {
      state = state.copyWith(stage: WebAuthStage.form, errorMessage: 'Could not sign in — $e');
    }
  }

  Future<void> signUp() async {
    final email = state.email.trim();
    final password = state.password;
    if (email.isEmpty || password.isEmpty) return;

    state = state.copyWith(stage: WebAuthStage.submitting, clearError: true);
    try {
      await _repository.signUp(email: email, password: password);
      state = state.copyWith(stage: WebAuthStage.awaitingVerification);
    } catch (e) {
      state = state.copyWith(stage: WebAuthStage.form, errorMessage: 'Could not create the account — $e');
    }
  }

  Future<void> resendVerificationEmail() async {
    try {
      await _repository.resendVerificationEmail();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Could not resend the email — $e');
    }
  }

  /// Called when the staff member says they've clicked the verification
  /// link. Finishes self-provisioning only if Firebase's own record
  /// (reloaded fresh) genuinely shows verified.
  Future<void> checkVerificationAndContinue() async {
    state = state.copyWith(stage: WebAuthStage.completingSignUp, clearError: true);
    try {
      await _repository.completeSignUp();
      state = state.copyWith(stage: WebAuthStage.done);
    } on EmailNotVerifiedException {
      state = state.copyWith(
        stage: WebAuthStage.awaitingVerification,
        errorMessage: 'Not verified yet — click the link in the email first, then try again.',
      );
    } catch (e) {
      state = state.copyWith(stage: WebAuthStage.form, errorMessage: 'Could not finish sign-up — $e');
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = const WebAuthState();
  }
}

// Real by default; tests override with a stubbed WebAuthRepository (see
// web_auth_repository_test.dart / web_auth_controller_test.dart).
final webAuthRepositoryProvider = Provider<WebAuthRepository>((ref) => WebAuthRepository());

final webAuthControllerProvider = StateNotifierProvider<WebAuthController, WebAuthState>(
  (ref) => WebAuthController(ref.watch(webAuthRepositoryProvider)),
);
