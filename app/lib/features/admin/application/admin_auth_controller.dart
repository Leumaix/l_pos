import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_auth_repository.dart';

enum AdminAuthStage {
  /// Entering the admin's email.
  form,
  sending,

  /// Link sent — waiting for the admin to open it in this same browser.
  linkSent,

  /// The link arrived (page reopened with it in the URL); completing
  /// sign-in.
  completingLink,

  /// Signed in — nothing further needed, no PIN step for this tool.
  done,
}

class AdminAuthState {
  final AdminAuthStage stage;
  final String email;
  final String? errorMessage;

  const AdminAuthState({this.stage = AdminAuthStage.form, this.email = '', this.errorMessage});

  AdminAuthState copyWith({
    AdminAuthStage? stage,
    String? email,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AdminAuthState(
      stage: stage ?? this.stage,
      email: email ?? this.email,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Deliberately not VerificationController — that one manages a whole
/// PIN-choosing/handoff state machine this tool has no equivalent of.
/// This is the plain email-link send/complete cycle only.
class AdminAuthController extends StateNotifier<AdminAuthState> {
  final AdminAuthRepository _repository;

  AdminAuthController(this._repository) : super(const AdminAuthState()) {
    // A signed-in admin reloading the tool (browser session persistence)
    // should land straight past the login screen — check once at
    // construction, same as how the mobile app's redirect checks
    // authRepository.currentUser.
    if (_repository.currentUser != null) {
      state = state.copyWith(stage: AdminAuthStage.done);
    }
  }

  void setEmail(String email) => state = state.copyWith(email: email, clearError: true);

  Future<void> sendLink() async {
    final email = state.email.trim();
    if (email.isEmpty) return;

    state = state.copyWith(stage: AdminAuthStage.sending, clearError: true);
    try {
      await _repository.sendSignInLink(email);
      state = state.copyWith(stage: AdminAuthStage.linkSent);
    } catch (e) {
      state = state.copyWith(
        stage: AdminAuthStage.form,
        errorMessage: 'Could not send the link — $e',
      );
    }
  }

  /// Called once at startup with the page's own URL — completes sign-in
  /// only if that URL is actually a sign-in link; a no-op otherwise (the
  /// ordinary "just opened the tool fresh" case).
  Future<void> completeSignInIfLinkPresent(String currentUrl) async {
    if (!_repository.isSignInWithEmailLink(currentUrl)) return;

    state = state.copyWith(stage: AdminAuthStage.completingLink, clearError: true);
    try {
      await _repository.completeSignInWithLink(currentUrl);
      state = state.copyWith(stage: AdminAuthStage.done);
    } catch (e) {
      state = state.copyWith(
        stage: AdminAuthStage.form,
        errorMessage: 'That link is invalid or expired — $e',
      );
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = const AdminAuthState();
  }
}

// Same "real by default, overridden with FakeAdminAuthRepository in
// tests" convention as every other repository provider in this app.
final adminAuthRepositoryProvider = Provider<AdminAuthRepository>(
  (ref) => FirebaseAdminAuthRepository(),
);

final adminAuthControllerProvider = StateNotifierProvider<AdminAuthController, AdminAuthState>(
  (ref) => AdminAuthController(ref.watch(adminAuthRepositoryProvider)),
);
