import '../domain/staff_invite.dart';

/// Owner-only management of pending staff invites — the in-app on-ramp
/// for adding staff, alongside the security rules that actually enforce
/// who can create/delete/read these documents (see firestore.rules).
/// Business creation itself stays vendor/console-only and has no
/// repository at all; this is only ever about adding staff to a business
/// that already exists.
abstract class StaffInviteRepository {
  Future<List<StaffInvite>> pendingInvites();

  /// Creates (or replaces, if one already exists for this email) an
  /// invite. [role] must be one of the app's known role values — the
  /// repository doesn't validate that itself; the caller (the Invite
  /// Staff screen's role picker) is the only place a role value
  /// originates from.
  Future<void> createInvite({required String email, required String name, required String role});

  Future<void> revokeInvite(String email);
}

class FakeStaffInviteRepository implements StaffInviteRepository {
  final Map<String, StaffInvite> _invites = {};

  @override
  Future<List<StaffInvite>> pendingInvites() async {
    return _invites.values.toList()..sort((a, b) => b.invitedAt.compareTo(a.invitedAt));
  }

  @override
  Future<void> createInvite({required String email, required String name, required String role}) async {
    final key = email.trim().toLowerCase();
    _invites[key] = StaffInvite(
      email: key,
      name: name.trim(),
      role: role,
      invitedAt: DateTime.now(),
      invitedBy: 'fake-owner-uid',
    );
  }

  @override
  Future<void> revokeInvite(String email) async {
    _invites.remove(email.trim().toLowerCase());
  }
}
