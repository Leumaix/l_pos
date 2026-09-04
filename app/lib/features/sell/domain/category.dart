/// Sentinel "category id" for Gas's pinned-first slot in the Sell/Stock/
/// Restock category picker. Never written to Firestore, never compared
/// against a real Category — purely a UI selection key, since Gas isn't
/// a Category document at all.
const kGasCategoryId = '__gas__';

/// An owner-defined product category (e.g. "Cylinders", "Accessories", or
/// anything else the owner adds later) — Gas is deliberately NOT one of
/// these: it has no owner-editable name/price/stock and keeps its own
/// hardcoded behavior everywhere, by design. See kGasCategoryId for how
/// the UI still gives Gas a pinned-first slot in the category picker
/// without it being a real Category document.
class Category {
  final String id;
  final String name;
  final int sortOrder;

  const Category({required this.id, required this.name, required this.sortOrder});
}
