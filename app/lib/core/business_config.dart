/// This install of Leumadepos is configured for exactly one business —
/// per the day-one decision, the data model is multi-tenant-ready
/// (everything lives under businesses/{businessId}/...) but the app itself
/// picks its business at compile time rather than offering a picker,
/// since that's all MVP scope needs.
///
/// IMPORTANT: this must match exactly the document ID Sammy creates at
/// businesses/{this value} in the Firestore console when provisioning
/// PH-Zazaa — the real Firestore-backed repositories all read/write under
/// this path. If it's ever changed here, the Firestore document (and
/// every staff doc under it) has to be renamed to match, or Leumadepos
/// will simply see no business at all.
const kBusinessId = 'ph-zazaa';

/// The Firebase project's default Hosting domain — deployed specifically
/// to support email-link auth now that Dynamic Links is gone. Must match
/// the domain in the AndroidManifest.xml intent-filter and the project's
/// actual Hosting site.
const kFirebaseHostingDomain = 'lpos-ac40b.firebaseapp.com';

/// Must match android/app/build.gradle.kts's applicationId exactly.
const kAndroidPackageName = 'com.leumade.pos';

/// Fallback used only while `businesses/{kBusinessId}.settings.gasTankCapacityKg`
/// hasn't been set yet (a fresh console-provisioned business doc, or a
/// brief load/error window) — matches the old hardcoded placeholder so
/// behavior doesn't silently change until an owner actually sets a real
/// value via the Settings screen.
const kDefaultGasTankCapacityKg = 100.0;

/// Fallback used both during the brief initial-load window before the
/// first `businesses/{kBusinessId}/gasStock/current.rate` snapshot
/// arrives (or a read error), AND — more consequentially — as the real,
/// implicit rate every kg-based gas sale/restock uses whenever this
/// business's `gasStock/current` doc has no `rate` field yet (ordinary
/// staff activity, not an owner, can create that doc with just `units`
/// before any owner ever visits Settings — see firestore.rules' gasStock
/// create rule). FirebaseInventoryRepository.changeGasRate's first-ever-
/// rate-set logic treats those already-recorded units as having been
/// priced at exactly this rate, preserving their physical kg rather than
/// discarding them — confirmed as a real, previously-broken case on a
/// live business, not a hypothetical.
///
/// firestore.rules' matching gasStock update rule (the one gating that
/// exact transition) hardcodes this same value as a literal `1400.0` —
/// rules have no way to reference a Dart constant. If this value ever
/// changes, that literal must change with it, or the two will silently
/// disagree about how much physical kg a business's already-recorded
/// units represent.
const kDefaultGasRateNairaPerKg = 1400;

