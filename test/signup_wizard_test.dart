import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/auth/presentation/sign_up_screen.dart';

void main() {
  test(
    'registration offers separate product, service, and restaurant types',
    () {
      expect(signupBusinessTypes, ['products', 'services', 'restaurant']);
      expect(signupBusinessTypeLabel('products'), 'Products');
      expect(signupBusinessTypeLabel('services'), 'Services');
      expect(signupBusinessTypeLabel('restaurant'), 'Restaurant');
    },
  );

  test('store link preview creates a readable subdomain', () {
    expect(
      signupStoreSlugPreview('Amina Fashion & Beauty'),
      'amina-fashion-and-beauty',
    );
  });

  test('store link preview protects reserved and numeric names', () {
    expect(signupStoreSlugPreview('Admin'), 'admin-shop');
    expect(signupStoreSlugPreview('12345'), 'shop-12345');
  });

  test('empty store link preview remains understandable', () {
    expect(signupStoreSlugPreview(''), 'your-business');
  });
}
