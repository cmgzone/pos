import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/settings/presentation/storefront_in_app_preview.dart';

void main() {
  test('preview selection preserves generated-site editing context', () {
    final selection = StorefrontComponentSelection.fromJson({
      'component': 'product-action',
      'selector': 'article[data-product-id="product-1"] > button',
      'label': 'Add to cart',
      'element': 'button',
      'scope': 'product-card:Bluetooth speaker',
      'dimensions': '180 × 40 px',
      'styles': 'display:flex; background:rgb(209,67,67)',
      'siteBuildId': 'site-build-1',
      'siteMode': 'single_product',
      'selectedProductId': 'product-1',
    });

    expect(selection.component, 'product-action');
    expect(selection.siteBuildId, 'site-build-1');
    expect(selection.siteMode, 'single_product');
    expect(selection.selectedProductId, 'product-1');
    expect(selection.toJson()['scope'], 'product-card:Bluetooth speaker');
    expect(selection.toJson()['styles'], contains('background'));
  });
}
