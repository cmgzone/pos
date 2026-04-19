import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'product_repository.dart';
import 'category_repository.dart';

// ──────────── Category Providers ────────────

final categoriesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return CategoryRepository.getAll();
});

final selectedCategoryProvider = StateProvider<String?>((ref) => null);

// ──────────── Product Providers ────────────

final productsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>((
      ref,
      categoryId,
    ) async {
      if (categoryId == null) {
        return ProductRepository.getAll();
      }
      return ProductRepository.getAll(categoryId: categoryId);
    });

final productSearchProvider = StateProvider<String>((ref) => '');

final filteredProductsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final search = ref.watch(productSearchProvider);
  final categoryId = ref.watch(selectedCategoryProvider);

  if (search.isNotEmpty) {
    return ProductRepository.search(search);
  }

  if (categoryId != null) {
    return ProductRepository.getAll(categoryId: categoryId);
  }

  return ProductRepository.getAll();
});

final lowStockProductsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ProductRepository.getLowStock();
});
