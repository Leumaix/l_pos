import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sell/application/inventory_providers.dart';
import '../../sell/domain/category.dart';
import '../../sell/domain/product.dart';

/// Owner-only catalog management actions — categories and products.
/// Deliberately a thin pass-through to InventoryRepository, same shape
/// as RestockController: the actual rules (who can do this) live in
/// firestore.rules, not here; this just forwards the call.
class ManageCatalogController {
  final Ref ref;

  ManageCatalogController(this.ref);

  Future<Category> createCategory(String name) =>
      ref.read(inventoryRepositoryProvider).createCategory(name);

  Future<void> renameCategory(String categoryId, String name) =>
      ref.read(inventoryRepositoryProvider).renameCategory(categoryId, name);

  Future<void> deleteCategory(String categoryId) =>
      ref.read(inventoryRepositoryProvider).deleteCategory(categoryId);

  Future<void> reorderCategories(List<String> orderedCategoryIds) =>
      ref.read(inventoryRepositoryProvider).reorderCategories(orderedCategoryIds);

  Future<Product> createProduct({
    required String categoryId,
    required String name,
    required int price,
    required int stockCount,
    required ProductUnit unit,
  }) => ref.read(inventoryRepositoryProvider).createProduct(
    categoryId: categoryId,
    name: name,
    price: price,
    stockCount: stockCount,
    unit: unit,
  );

  Future<void> updateProduct({
    required String productId,
    required String name,
    required int price,
    required ProductUnit unit,
  }) => ref.read(inventoryRepositoryProvider).updateProduct(
    productId: productId,
    name: name,
    price: price,
    unit: unit,
  );

  Future<void> deleteProduct(String productId) =>
      ref.read(inventoryRepositoryProvider).deleteProduct(productId);
}

final manageCatalogControllerProvider = Provider((ref) => ManageCatalogController(ref));
