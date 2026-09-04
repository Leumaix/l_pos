enum ProductUnit { piece, yard }

/// A cylinder, accessory, or anything else in the owner-managed catalog.
/// Gas is deliberately not a [Product] — it has no fixed unit price or
/// discrete stock count; it's priced per kg via the business's gas rate
/// and tracked in units (see package:gas_stock).
class Product {
  final String id;
  final String categoryId;
  final String name;
  final int price; // whole naira
  final int stockCount;
  final ProductUnit unit;

  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.price,
    required this.stockCount,
    this.unit = ProductUnit.piece,
  });

  Product copyWith({int? stockCount}) => Product(
    id: id,
    categoryId: categoryId,
    name: name,
    price: price,
    stockCount: stockCount ?? this.stockCount,
    unit: unit,
  );
}
