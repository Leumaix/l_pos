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

/// Fallback used only during the brief initial-load window before the
/// first `businesses/{kBusinessId}/gasStock/current.rate` snapshot
/// arrives (or a read error) — matches the rate this whole app has been
/// hardcoded to until now, so nothing silently changes for that window.
/// Unlike capacity, there's no "unset" case in normal operation: rate
/// must always exist in Firestore by the time any rate-change transaction
/// runs, since the transaction needs a real current rate to preserve kg
/// against — see FirebaseInventoryRepository.changeGasRate.
const kDefaultGasRateNairaPerKg = 1400;

