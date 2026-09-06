import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/business_onboarding_repository.dart';
import 'admin_auth_controller.dart';

/// Lowercase letters, digits, and single hyphens between them — this
/// becomes a real Firestore document id and, eventually, a
/// kBusinessId-style compile-time constant for whatever build gets
/// configured for this business. No leading/trailing hyphen, no
/// consecutive hyphens, so it's never ambiguous when read back.
final _slugPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

bool isValidBusinessSlug(String value) => _slugPattern.hasMatch(value.trim());

class AdminOnboardingState {
  final String businessId;
  final String businessName;
  final String ownerName;
  final String ownerEmail;
  final bool submitting;
  final String? errorMessage;

  /// Set only right after a successful submit — carries the values that
  /// were just onboarded, since the form fields themselves are cleared
  /// on success (same "reset on success" convention as every other form
  /// controller in this app).
  final ({String businessId, String ownerEmail})? justOnboarded;

  const AdminOnboardingState({
    this.businessId = '',
    this.businessName = '',
    this.ownerName = '',
    this.ownerEmail = '',
    this.submitting = false,
    this.errorMessage,
    this.justOnboarded,
  });

  bool get canSubmit =>
      !submitting &&
      isValidBusinessSlug(businessId) &&
      businessName.trim().isNotEmpty &&
      ownerName.trim().isNotEmpty &&
      ownerEmail.trim().isNotEmpty;

  AdminOnboardingState copyWith({
    String? businessId,
    String? businessName,
    String? ownerName,
    String? ownerEmail,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AdminOnboardingState(
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      ownerName: ownerName ?? this.ownerName,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      submitting: submitting ?? this.submitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      // justOnboarded is deliberately NOT carried through copyWith — it's
      // a one-shot success signal, only ever set directly by submit()
      // itself, and cleared the moment the admin touches the form again.
    );
  }
}

class AdminOnboardingController extends StateNotifier<AdminOnboardingState> {
  final Ref ref;

  AdminOnboardingController(this.ref) : super(const AdminOnboardingState());

  void setBusinessId(String value) => state = state.copyWith(businessId: value.trim().toLowerCase(), clearError: true);
  void setBusinessName(String value) => state = state.copyWith(businessName: value, clearError: true);
  void setOwnerName(String value) => state = state.copyWith(ownerName: value, clearError: true);
  void setOwnerEmail(String value) => state = state.copyWith(ownerEmail: value, clearError: true);

  Future<bool> submit() async {
    if (!state.canSubmit) return false;

    final businessId = state.businessId.trim();
    final ownerEmail = state.ownerEmail.trim().toLowerCase();

    state = state.copyWith(submitting: true, clearError: true);
    try {
      await ref
          .read(businessOnboardingRepositoryProvider)
          .onboardBusiness(
            businessId: businessId,
            businessName: state.businessName.trim(),
            ownerName: state.ownerName.trim(),
            ownerEmail: ownerEmail,
          );
      state = AdminOnboardingState(justOnboarded: (businessId: businessId, ownerEmail: ownerEmail));
      return true;
    } on BusinessIdTakenException {
      state = state.copyWith(submitting: false, errorMessage: 'That business ID is already taken — pick another.');
      return false;
    } catch (e) {
      state = state.copyWith(submitting: false, errorMessage: 'Could not onboard that business — $e');
      return false;
    }
  }
}

// Same "real by default, overridden with Fake in tests" convention as
// every other repository provider in this app.
final businessOnboardingRepositoryProvider = Provider<BusinessOnboardingRepository>(
  (ref) => FirebaseBusinessOnboardingRepository(ref.watch(adminAuthRepositoryProvider)),
);

final adminOnboardingControllerProvider =
    StateNotifierProvider.autoDispose<AdminOnboardingController, AdminOnboardingState>(
      (ref) => AdminOnboardingController(ref),
    );
