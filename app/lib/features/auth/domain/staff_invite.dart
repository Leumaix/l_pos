/// A pending, owner-issued invitation for someone to become staff on this
/// business — the in-app alternative to console provisioning. [email] is
/// also the invite's Firestore document ID (lowercased, trimmed), since a
/// staff member's own self-provisioning lookup needs to find it by their
/// signed-in email with no separate index.
class StaffInvite {
  final String email;
  final String name;
  final String role;
  final DateTime invitedAt;
  final String invitedBy;

  const StaffInvite({
    required this.email,
    required this.name,
    required this.role,
    required this.invitedAt,
    required this.invitedBy,
  });
}
