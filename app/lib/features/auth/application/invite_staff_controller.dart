import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/staff_invite_repository.dart';
import '../domain/staff_invite.dart';
import 'auth_providers.dart';

const kStaffRoles = ['attendant', 'owner'];

class InviteStaffState {
  final List<StaffInvite> invites;
  final bool loadingInvites;
  final String name;
  final String email;
  final String role;
  final bool submitting;
  final String? errorMessage;

  const InviteStaffState({
    this.invites = const [],
    this.loadingInvites = true,
    this.name = '',
    this.email = '',
    this.role = 'attendant',
    this.submitting = false,
    this.errorMessage,
  });

  bool get canSubmit => !submitting && name.trim().isNotEmpty && email.trim().isNotEmpty;

  InviteStaffState copyWith({
    List<StaffInvite>? invites,
    bool? loadingInvites,
    String? name,
    String? email,
    String? role,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return InviteStaffState(
      invites: invites ?? this.invites,
      loadingInvites: loadingInvites ?? this.loadingInvites,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      submitting: submitting ?? this.submitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class InviteStaffController extends StateNotifier<InviteStaffState> {
  final StaffInviteRepository _repository;

  InviteStaffController(this._repository) : super(const InviteStaffState()) {
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    state = state.copyWith(loadingInvites: true);
    try {
      final invites = await _repository.pendingInvites();
      state = state.copyWith(invites: invites, loadingInvites: false);
    } catch (_) {
      state = state.copyWith(loadingInvites: false, errorMessage: 'Could not load pending invites.');
    }
  }

  void setName(String name) => state = state.copyWith(name: name, clearError: true);
  void setEmail(String email) => state = state.copyWith(email: email, clearError: true);
  void setRole(String role) => state = state.copyWith(role: role, clearError: true);

  Future<bool> submit() async {
    if (!state.canSubmit) return false;

    state = state.copyWith(submitting: true, clearError: true);
    try {
      await _repository.createInvite(email: state.email.trim(), name: state.name.trim(), role: state.role);
      final invites = await _repository.pendingInvites();
      state = InviteStaffState(invites: invites, loadingInvites: false);
      return true;
    } catch (_) {
      state = state.copyWith(submitting: false, errorMessage: 'Could not send that invite. Try again.');
      return false;
    }
  }

  Future<void> revoke(String email) async {
    try {
      await _repository.revokeInvite(email);
      state = state.copyWith(invites: state.invites.where((invite) => invite.email != email).toList());
    } catch (_) {
      state = state.copyWith(errorMessage: 'Could not revoke that invite. Try again.');
    }
  }
}

final inviteStaffControllerProvider =
    StateNotifierProvider.autoDispose<InviteStaffController, InviteStaffState>(
      (ref) => InviteStaffController(ref.watch(staffInviteRepositoryProvider)),
    );
