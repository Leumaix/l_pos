import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gas_stock/gas_stock.dart';

import '../../../core/business_config.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/category.dart';
import '../domain/product.dart';
import 'inventory_repository.dart';

/// Real implementation for the owner-managed catalog (categories +
/// products) AND gas stock — reads/writes through whoever is CURRENTLY
/// ACTIVE's authenticated Firestore session (see
/// FirebaseAuthRepository.activeFirestore), same pattern as the invite
/// and business-settings repositories.
///
/// Gas stock lives at a single doc, businesses/{id}/gasStock/current
/// ({units: int, rate: num}), with every deduction/addition also
/// appending a businesses/{id}/gasStockLedger entry (append-only audit
/// trail; see firestore.rules — create-only, no update/delete). Both
/// writes go through one WriteBatch so the stock change and its ledger
/// entry are never observable apart. Changing the rate itself
/// (changeGasRate) similarly pairs a rate+units write with its own
/// ledger entry, but through one runTransaction instead of a batch — it
/// needs to READ the current rate/units first to compute the new units,
/// which a batch can't do.
class FirebaseInventoryRepository implements InventoryRepository {
  final AuthRepository _firebaseAuth;

  GasStock _cachedGasStock = GasStock.zero;
  StreamSubscription<GasStock>? _gasStockSubscription;

  GasRate _cachedGasRate = const GasRate(kDefaultGasRateNairaPerKg);
  StreamSubscription<GasRate>? _gasRateSubscription;

  List<Product> _cachedProducts = const [];
  StreamSubscription<List<Product>>? _productsSubscription;

  List<Category> _cachedCategories = const [];
  StreamSubscription<List<Category>>? _categoriesSubscription;

  FirebaseInventoryRepository(this._firebaseAuth);

  FirebaseFirestore get _firestore {
    final firestore = _firebaseAuth.activeFirestore;
    if (firestore == null) {
      throw StateError('InventoryRepository used with nobody currently signed in.');
    }
    return firestore;
  }

  CollectionReference<Map<String, dynamic>> get _productsCollection =>
      _firestore.collection('businesses/$kBusinessId/products');

  CollectionReference<Map<String, dynamic>> get _categoriesCollection =>
      _firestore.collection('businesses/$kBusinessId/categories');

  DocumentReference<Map<String, dynamic>> get _gasStockDoc =>
      _firestore.doc('businesses/$kBusinessId/gasStock/current');

  CollectionReference<Map<String, dynamic>> get _gasStockLedgerCollection =>
      _firestore.collection('businesses/$kBusinessId/gasStockLedger');

  @override
  Stream<GasRate> watchGasRate() {
    return _gasStockDoc.snapshots().map((doc) {
      final rate = doc.data()?['rate'];
      if (rate == null) return const GasRate(kDefaultGasRateNairaPerKg);
      return GasRate(rate as num);
    });
  }

  @override
  GasRate get gasRate {
    // Same lazily-started cache contract as currentGasStock.
    _gasRateSubscription ??= watchGasRate().listen((rate) => _cachedGasRate = rate);
    return _cachedGasRate;
  }

  @override
  Future<void> changeGasRate(GasRate newRate, {required String staffId, required String staffName}) async {
    await _firestore.runTransaction((transaction) async {
      // All reads in a Firestore transaction must happen before any
      // writes — this get() has to come first.
      final snapshot = await transaction.get(_gasStockDoc);
      final data = snapshot.data();
      final oldRateValue = data?['rate'];
      if (oldRateValue == null) {
        // No rate has ever been set for this business — a freshly
        // onboarded business (see the super-admin onboarding tool, which
        // deliberately writes nothing gas-specific) has no gasStock/
        // current doc at all yet. There's no old rate to preserve
        // physical kg against, so this is an initialization, not a
        // change: units starts at 0 (no prior physical stock to
        // preserve, since none was ever seeded) and the ledger entry
        // says so honestly rather than looking like a rateChange with a
        // fabricated "before" state.
        transaction.set(_gasStockDoc, {
          'rate': newRate.nairaPerKg,
          'units': 0,
        }, SetOptions(merge: true));
        transaction.set(_gasStockLedgerCollection.doc(), {
          'type': 'initialize',
          'unitsDelta': 0,
          'oldRate': null,
          'newRate': newRate.nairaPerKg,
          'staffId': staffId,
          'staffName': staffName,
          'saleId': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      final oldRate = GasRate(oldRateValue as num);
      final oldStock = GasStock((data?['units'] as num? ?? 0).toInt());
      final result = changeRate(oldStock, oldRate, newRate);

      transaction.set(_gasStockDoc, {
        'rate': newRate.nairaPerKg,
        'units': result.stock.units,
      }, SetOptions(merge: true));
      transaction.set(_gasStockLedgerCollection.doc(), {
        'type': 'rateChange',
        'unitsDelta': result.stock.units - oldStock.units,
        'oldRate': oldRate.nairaPerKg,
        'newRate': newRate.nairaPerKg,
        'preservedKg': result.preservedKg,
        'staffId': staffId,
        'staffName': staffName,
        'saleId': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<(GasRate, GasStock)> fetchCurrentRateAndStock() async {
    // One fresh .get(), not the cached gasRate/currentGasStock getters —
    // see this method's doc comment on the interface for why those can
    // still be showing their cold-start default the first time they're
    // ever accessed. Same document both values come from, so they can
    // never be split across two different moments in time either.
    final doc = await _gasStockDoc.get();
    final data = doc.data();
    final rateValue = data?['rate'];
    final rate = rateValue == null ? const GasRate(kDefaultGasRateNairaPerKg) : GasRate(rateValue as num);
    final stock = GasStock((data?['units'] as num? ?? 0).toInt());
    return (rate, stock);
  }

  @override
  Stream<GasStock> watchGasStock() {
    return _gasStockDoc.snapshots().map(
      (doc) => GasStock((doc.data()?['units'] as num? ?? 0).toInt()),
    );
  }

  @override
  GasStock get currentGasStock {
    // Best-effort, lazily-started cache — same "don't wait on the
    // stream" contract as currentProducts. Starts at GasStock.zero until
    // the first snapshot arrives (a real, provisioned business always
    // has a gasStock/current doc — see the deploy note on seeding it).
    _gasStockSubscription ??= watchGasStock().listen((stock) => _cachedGasStock = stock);
    return _cachedGasStock;
  }

  Future<void> _applyGasDelta(
    int delta, {
    required String type,
    required String staffId,
    required String staffName,
    String? saleId,
  }) async {
    final batch = _firestore.batch();
    batch.set(_gasStockDoc, {'units': FieldValue.increment(delta)}, SetOptions(merge: true));
    batch.set(_gasStockLedgerCollection.doc(), {
      'type': type,
      'unitsDelta': delta,
      'staffId': staffId,
      'staffName': staffName,
      'saleId': saleId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  @override
  Future<void> deductGasStock(int units, {required String staffId, required String staffName}) {
    return _applyGasDelta(-units, type: 'sale', staffId: staffId, staffName: staffName);
  }

  @override
  Future<void> addGasStock(int units, {required String staffId, required String staffName}) {
    return _applyGasDelta(units, type: 'restock', staffId: staffId, staffName: staffName);
  }

  Product _productFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Product(
      id: doc.id,
      categoryId: data['categoryId'] as String,
      name: data['name'] as String,
      price: (data['price'] as num).toInt(),
      stockCount: (data['stockCount'] as num).toInt(),
      unit: data['unit'] == 'yard' ? ProductUnit.yard : ProductUnit.piece,
    );
  }

  Category _categoryFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Category(
      id: doc.id,
      name: data['name'] as String,
      sortOrder: (data['sortOrder'] as num).toInt(),
    );
  }

  @override
  Stream<List<Product>> watchProducts() {
    return _productsCollection.snapshots().map(
      (snapshot) => snapshot.docs.map(_productFromDoc).toList(),
    );
  }

  @override
  List<Product> get currentProducts {
    // Best-effort, lazily-started cache — mirrors currentGasStock's
    // "don't wait on the stream" contract, but Firestore has no
    // synchronous read; this returns whatever's arrived so far (empty
    // until the first snapshot, same as any cold cache).
    _productsSubscription ??= watchProducts().listen((products) => _cachedProducts = products);
    return _cachedProducts;
  }

  @override
  Stream<List<Category>> watchCategories() {
    return _categoriesCollection.orderBy('sortOrder').snapshots().map(
      (snapshot) => snapshot.docs.map(_categoryFromDoc).toList(),
    );
  }

  @override
  List<Category> get currentCategories {
    _categoriesSubscription ??= watchCategories().listen((categories) => _cachedCategories = categories);
    return _cachedCategories;
  }

  @override
  Future<void> decrementProductStock(String productId, int quantity) async {
    await _productsCollection.doc(productId).update({
      'stockCount': FieldValue.increment(-quantity),
    });
  }

  @override
  Future<void> incrementProductStock(String productId, int quantityAdded) async {
    await _productsCollection.doc(productId).update({
      'stockCount': FieldValue.increment(quantityAdded),
    });
  }

  @override
  Future<Category> createCategory(String name) async {
    final existing = await _categoriesCollection.get();
    final sortOrder = existing.docs.isEmpty
        ? 0
        : existing.docs.map((doc) => (doc.data()['sortOrder'] as num).toInt()).reduce((a, b) => a > b ? a : b) + 1;

    final ref = _categoriesCollection.doc();
    await ref.set({'name': name.trim(), 'sortOrder': sortOrder});
    return Category(id: ref.id, name: name.trim(), sortOrder: sortOrder);
  }

  @override
  Future<void> renameCategory(String categoryId, String name) async {
    await _categoriesCollection.doc(categoryId).update({'name': name.trim()});
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    // Checked live against Firestore, not the local cache — this is an
    // app-level "never orphan a product" guarantee, not something
    // firestore.rules can express (rules can't query "does any product
    // reference this category", only check specific known document
    // paths).
    final productsInCategory = await _productsCollection.where('categoryId', isEqualTo: categoryId).get();
    if (productsInCategory.docs.isNotEmpty) {
      throw CategoryNotEmptyException(productsInCategory.docs.length);
    }
    await _categoriesCollection.doc(categoryId).delete();
  }

  @override
  Future<void> reorderCategories(List<String> orderedCategoryIds) async {
    final batch = _firestore.batch();
    for (var i = 0; i < orderedCategoryIds.length; i++) {
      batch.update(_categoriesCollection.doc(orderedCategoryIds[i]), {'sortOrder': i});
    }
    await batch.commit();
  }

  @override
  Future<Product> createProduct({
    required String categoryId,
    required String name,
    required int price,
    required int stockCount,
    ProductUnit unit = ProductUnit.piece,
  }) async {
    final ref = _productsCollection.doc();
    await ref.set({
      'categoryId': categoryId,
      'name': name.trim(),
      'price': price,
      'stockCount': stockCount,
      'unit': unit == ProductUnit.yard ? 'yard' : 'piece',
    });
    return Product(
      id: ref.id,
      categoryId: categoryId,
      name: name.trim(),
      price: price,
      stockCount: stockCount,
      unit: unit,
    );
  }

  @override
  Future<void> updateProduct({
    required String productId,
    required String name,
    required int price,
    required ProductUnit unit,
  }) async {
    await _productsCollection.doc(productId).update({
      'name': name.trim(),
      'price': price,
      'unit': unit == ProductUnit.yard ? 'yard' : 'piece',
    });
  }

  @override
  Future<void> deleteProduct(String productId) async {
    await _productsCollection.doc(productId).delete();
  }
}
