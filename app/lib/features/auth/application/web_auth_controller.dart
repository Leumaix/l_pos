import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/web_auth_repository.dart';

enum WebAuthStage {
  /// Entering the staff member's email.
  form,
  sending,

  /// Link sent — waiting for them to open it in this same browser.
  linkSent,

  /// The link arrived (page reopened with it in the URL); completing
  /// sign-in.
  completingLink,

  /// Signed in — nothing further needed, no PIN step for this build.
  done,
}

class WebAuthState {
  final WebAuthStage stage;
  final String email;
  final String? errorMessage;

  const WebAuthState({this.stage = WebAuthStage.form, this.email = '', this.errorMessage});

  WebAuthState copyWith({
    WebAuthStage? stage,
    String? email,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WebAuthState(
      stage: stage ?? this.stage,
      email: email ?? this.email,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Plain email-link send/complete cycle for the web/PWA build — same shape
/// as AdminAuthController (that one's the proven precedent this mirrors),
/// but producing a REAL staff AppUser (with role, via WebAuthRepository's
/// staff-doc lookup/self-provisioning) rather than AdminAuthController's
/// bare uid+email. Deliberately depends on WebAuthRepository at its
/// CONCRETE type, not the abstract AuthRepository — isSignInWithEmailLink
/// (needed below) is intentionally not on that shared interface, since no
/// other consumer of it (the router, the other Firebase-backed
/// repositories) needs it; this controller is inherently web-only and will
/// never need swapping to a different AuthRepository implementation.
class WebAuthController extends StateNotifier<WebAuthState> {
  final WebAuthRepository _repository;

  WebAuthController(this._repository) : super(const WebAuthState()) {
    // A signed-in staff member reloading the page (browser session
    // persistence) should land straight past the login screen — checked
    // once at construction, same as AdminAuthController.
    if (_repository.currentUser != null) {
      state = state.copyWith(stage: WebAuthStage.done);
    }
  }

  void setEmail(String email) => state = state.copyWith(email: email, clearError: true);

  Future<void> sendLink() async {
    final email = state.email.trim();
    if (email.isEmpty) return;

    state = state.copyWith(stage: WebAuthStage.sending, clearError: true);
    try {
      await _repository.sendVerificationLink(email);
      state = state.copyWith(stage: WebAuthStage.linkSent);
    } catch (e) {
      state = state.copyWith(stage: WebAuthStage.form, errorMessage: 'Could not send the link — $e');
    }
  }

  /// Called once at startup with the page's own URL — completes sign-in
  /// only if that URL is actually a sign-in link; a no-op otherwise (the
  /// ordinary "just opened the app fresh" case).
  Future<void> completeSignInIfLinkPresent(String currentUrl) async {
    if (!_repository.isSignInWithEmailLink(currentUrl)) return;

    final pendingEmail = await _repository.pendingVerificationEmail();
    if (pendingEmail == null) {
      state = state.copyWith(
        stage: WebAuthStage.form,
        errorMessage:
            'No pending sign-in email remembered on this browser — the link may have been opened somewhere '
            'else, or storage was cleared. Send a new link from this browser.',
      );
      return;
    }

    state = state.copyWith(stage: WebAuthStage.completingLink, clearError: true);
    try {
      await _repository.completeEmailLinkSignIn(email: pendingEmail, emailLink: currentUrl);
      state = state.copyWith(stage: WebAuthStage.done);
    } catch (e) {
      state = state.copyWith(stage: WebAuthStage.form, errorMessage: 'That link is invalid or expired — $e');
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = const WebAuthState();
  }
}

// Real by default; tests override with a fake WebAuthRepository (see
// web_login_screen_test.dart).
final webAuthRepositoryProvider = Provider<WebAuthRepository>((ref) => WebAuthRepository());

final webAuthControllerProvider = StateNotifierProvider<WebAuthController, WebAuthState>(
  (ref) => WebAuthController(ref.watch(webAuthRepositoryProvider)),
);
