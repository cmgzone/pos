import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/utils/error_messages.dart';

void main() {
  group('AppErrorMessage', () {
    test('keeps simple customer-facing validation messages', () {
      expect(
        AppErrorMessage.from(Exception('Enter both email and password.')),
        'Enter both email and password.',
      );
      expect(
        AppErrorMessage.from(Exception('Not enough stock in this branch')),
        'Not enough stock in this branch.',
      );
    });

    test('maps network and server errors to friendly messages', () {
      expect(
        AppErrorMessage.from(
          'DioException [connection error]: SocketException: Failed host lookup: api.example.com',
        ),
        'The server could not be reached. Check your internet connection and try again.',
      );
      expect(
        AppErrorMessage.from('HTTP 500 Internal Server Error'),
        'The server had a problem. Please try again shortly.',
      );
    });

    test('hides implementation details', () {
      expect(
        AppErrorMessage.from(
          "DatabaseException(no such table: products) sql 'SELECT * FROM products'",
          fallback: AppErrorMessage.loadFailed,
        ),
        AppErrorMessage.loadFailed,
      );
      expect(
        AppErrorMessage.from(
          "type 'Null' is not a subtype of type 'String'",
          fallback: AppErrorMessage.generic,
        ),
        AppErrorMessage.generic,
      );
    });
  });
}
