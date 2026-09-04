import 'dart:async';

import 'package:gas_stock/gas_stock.dart';

import '../../../core/utils/replay_stream.dart';
import '../domain/category.dart';
import '../domain/product.dart';

/// Thrown by [InventoryRepository.deleteCategory] when products still
/// reference it — deleting must never orphan a product with a dangling
/// categoryId. The owner has to move or delete those products first.
class CategoryNotEmptyException implements Exception {
  final int productCount;
  const CategoryNotEmptyException(this.productCount);
}

/// Gas stock/rate + the owner-managed product catalog (categories +
/// products), as needed by the Sell, Payment, Stock, Restock, and Manage
/// Catalog screens. Backed by Firestore once that's wired up — see
/// [FakeInventoryRepository] for the stand-in used until then.
///
/// Gas is deliberately excluded from the catalog-management methods
/// below (createCategory, createProduct, etc.) — it has no owner-editable
/// name/price/stock and keeps its own hardcoded behavior everywhere,
/// by design (see kGasCategoryId).
///
/// [deductGasStock], [addGasStock], [decrementProductStock], and
/// [incrementProductStock] are all commit-time mutations — called only
/// once a sale (CheckoutController) or a restock (RestockController) is
/// confirmed, never speculatively. Both controllers' doc comments explain
/// why that separation matters.
abstract class InventoryRepository {
  Stream<GasStock> watchGasStock();

  /// Synchronous access to the current gas stock, for a controller that
  /// needs it as an input to a pure gas_stock computation (restock, a
  /// sale) without waiting on the stream. Mirrors AuthRepository.currentUser.
  GasStock get currentGasStock;

  GasRate get gasRate;

  Stream<List<Product>> watchProducts();

  /// Synchronous access to the current catalog — same rationale as
  /// [currentGasStock]: lets a caller (or a test) read the latest state
  /// without waiting on the stream.
  List<Product> get currentProducts;

  Stream<List<Category>> watchCategories();

  List<Category> get currentCategories;

  /// [staffId]/[staffName] attribute the gasStockLedger audit entry the
  /// real (Firestore) implementation writes alongside the deduction —
  /// unused by the fake, but part of the interface so every call site
  /// carries who did it.
  Future<void> deductGasStock(int units, {required String staffId, required String staffName});

  /// Adds [units] on top of whatever gas stock already exists — restock
  /// delivery. Never overwrites; see gas_stock's restock() docs.
  Future<void> addGasStock(int units, {required String staffId, required String staffName});

  Future<void> decrementProductStock(String productId, int quantity);

  /// Adds [quantityAdded] on top of whatever stock a product already
  /// has — a restock delivery, same additive-never-overwrite contract as
  /// [addGasStock]. See RestockController.commitProductRestock.
  Future<void> incrementProductStock(String productId, int quantityAdded);

  // --- Owner-only catalog management (see firestore.rules: gated to an
  // active owner; staff can still read everything above, and can still
  // move stockCount via a sale/restock, but can't reach any of these). ---

  /// Appended after whatever categories already exist (highest sortOrder
  /// + 1) — new categories land at the end of the picker, not wherever.
  Future<Category> createCategory(String name);

  Future<void> renameCategory(String categoryId, String name);

  /// Throws [CategoryNotEmptyException] if any product still references
  /// this category — never orphans a product with a dangling categoryId.
  Future<void> deleteCategory(String categoryId);

  /// Re-numbers every category's sortOrder to match its index in
  /// [orderedCategoryIds] (which must list every existing category id
  /// exactly once).
  Future<void> reorderCategories(List<String> orderedCategoryIds);

  Future<Product> createProduct({
    required String categoryId,
    required String name,
    required int price,
    required int stockCount,
    ProductUnit unit = ProductUnit.piece,
  });

  /// Deliberately name/price/unit only — never stockCount. Stock only
  /// ever moves through [incrementProductStock]/[decrementProductStock],
  /// so there's exactly one place that can ever change how much of
  /// something exists, restock/sale or otherwise.
  Future<void> updateProduct({
    required String productId,
    required String name,
    required int price,
    required ProductUnit unit,
  });

  Future<void> deleteProduct(String productId);
}

/// Seed catalog and pricing — placeholder figures for development only.
/// Real prices, stock counts, and the gas rate need to come from the
/// business owner once Firestore is set up; nothing here should be taken
/// as the actual PH-Zazaa price list.
class FakeInventoryRepository implements InventoryRepository {
  GasStock _gasStock = const GasStock(63000); // 45kg on hand
  final _gasStockController = StreamController<GasStock>.broadcast();

  List<Category> _categories = const [
    Category(id: 'cat-cylinders', name: 'Cylinders', sortOrder: 0),
    Category(id: 'cat-accessories', name: 'Accessories', sortOrder: 1),
  ];
  final _categoriesController = StreamController<List<Category>>.broadcast();

  List<Product> _products = const [
    Product(
      id: 'cyl-3kg',
      categoryId: 'cat-cylinders',
      name: '3kg Cylinder',
      price: 8000,
      stockCount: 12,
    ),
    Product(
      id: 'cyl-6kg',
      categoryId: 'cat-cylinders',
      name: '6kg Cylinder',
      price: 15000,
      stockCount: 9,
    ),
    Product(
      id: 'cyl-12.5kg',
      categoryId: 'cat-cylinders',
      name: '12.5kg Cylinder',
      price: 28000,
      stockCount: 5,
    ),
    Product(
      id: 'cyl-50kg',
      categoryId: 'cat-cylinders',
      name: '50kg Cylinder',
      price: 95000,
      stockCount: 2,
    ),
    Product(
      id: 'acc-regulator',
      categoryId: 'cat-accessories',
      name: 'Gas Regulator',
      price: 6500,
      stockCount: 15,
    ),
    Product(
      id: 'acc-hose',
      categoryId: 'cat-accessories',
      name: 'Gas Hose',
      price: 800,
      stockCount: 40,
      unit: ProductUnit.yard,
    ),
    Product(
      id: 'acc-burner',
      categoryId: 'cat-accessories',
      name: 'Gas Burner',
      price: 12000,
      stockCount: 8,
    ),
    Product(
      id: 'acc-lighter',
      categoryId: 'cat-accessories',
      name: 'Lighter',
      price: 300,
      stockCount: 50,
    ),
  ];
  final _productsController = StreamController<List<Product>>.broadcast();

  int _nextId = 1;
  String _generateId(String prefix) => '$prefix-fake-${_nextId++}';

  @override
  GasRate get gasRate => const GasRate(1400);

  @override
  GasStock get currentGasStock => _gasStock;

  @override
  Stream<GasStock> watchGasStock() => replayLatest(() => _gasStock, _gasStockController.stream);

  @override
  List<Product> get currentProducts => _products;

  @override
  Stream<List<Product>> watchProducts() =>
      replayLatest(() => _products, _productsController.stream);

  @override
  List<Category> get currentCategories => _categories;

  @override
  Stream<List<Category>> watchCategories() =>
      replayLatest(() => _categories, _categoriesController.stream);

  @override
  Future<void> deductGasStock(int units, {required String staffId, required String staffName}) async {
    _gasStock = GasStock(_gasStock.units - units);
    _gasStockController.add(_gasStock);
  }

  @override
  Future<void> addGasStock(int units, {required String staffId, required String staffName}) async {
    _gasStock = GasStock(_gasStock.units + units);
    _gasStockController.add(_gasStock);
  }

  @override
  Future<void> decrementProductStock(String productId, int quantity) async {
    _products = [
      for (final product in _products)
        if (product.id == productId)
          product.copyWith(stockCount: product.stockCount - quantity)
        else
          product,
    ];
    _productsController.add(_products);
  }

  @override
  Future<void> incrementProductStock(String productId, int quantityAdded) async {
    _products = [
      for (final product in _products)
        if (product.id == productId)
          product.copyWith(stockCount: product.stockCount + quantityAdded)
        else
          product,
    ];
    _productsController.add(_products);
  }

  @override
  Future<Category> createCategory(String name) async {
    final sortOrder = _categories.isEmpty
        ? 0
        : _categories.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final category = Category(id: _generateId('cat'), name: name.trim(), sortOrder: sortOrder);
    _categories = [..._categories, category];
    _categoriesController.add(_categories);
    return category;
  }

  @override
  Future<void> renameCategory(String categoryId, String name) async {
    _categories = [
      for (final category in _categories)
        if (category.id == categoryId)
          Category(id: category.id, name: name.trim(), sortOrder: category.sortOrder)
        else
          category,
    ];
    _categoriesController.add(_categories);
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    final productCount = _products.where((p) => p.categoryId == categoryId).length;
    if (productCount > 0) {
      throw CategoryNotEmptyException(productCount);
    }
    _categories = _categories.where((c) => c.id != categoryId).toList();
    _categoriesController.add(_categories);
  }

  @override
  Future<void> reorderCategories(List<String> orderedCategoryIds) async {
    final byId = {for (final category in _categories) category.id: category};
    _categories = [
      for (var i = 0; i < orderedCategoryIds.length; i++)
        if (byId[orderedCategoryIds[i]] case final category?)
          Category(id: category.id, name: category.name, sortOrder: i),
    ];
    _categoriesController.add(_categories);
  }

  @override
  Future<Product> createProduct({
    required String categoryId,
    required String name,
    required int price,
    required int stockCount,
    ProductUnit unit = ProductUnit.piece,
  }) async {
    final product = Product(
      id: _generateId('prod'),
      categoryId: categoryId,
      name: name.trim(),
      price: price,
      stockCount: stockCount,
      unit: unit,
    );
    _products = [..._products, product];
    _productsController.add(_products);
    return product;
  }

  @override
  Future<void> updateProduct({
    required String productId,
    required String name,
    required int price,
    required ProductUnit unit,
  }) async {
    _products = [
      for (final product in _products)
        if (product.id == productId)
          Product(
            id: product.id,
            categoryId: product.categoryId,
            name: name.trim(),
            price: price,
            stockCount: product.stockCount,
            unit: unit,
          )
        else
          product,
    ];
    _productsController.add(_products);
  }

  @override
  Future<void> deleteProduct(String productId) async {
    _products = _products.where((p) => p.id != productId).toList();
    _productsController.add(_products);
  }
}
