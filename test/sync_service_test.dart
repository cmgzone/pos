import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/sync_service.dart';

void main() {
  test('pull order applies parent rows before customer invoices and items', () {
    final order = SyncService.pullTableOrderForTesting;

    expect(order.indexOf('sales'), greaterThanOrEqualTo(0));
    expect(order.indexOf('services'), greaterThanOrEqualTo(0));
    expect(order.indexOf('customer_invoices'), greaterThanOrEqualTo(0));
    expect(order.indexOf('customer_invoice_items'), greaterThanOrEqualTo(0));

    expect(order.indexOf('sales'), lessThan(order.indexOf('customer_invoices')));
    expect(
      order.indexOf('services'),
      lessThan(order.indexOf('customer_invoice_items')),
    );
    expect(
      order.indexOf('customer_invoices'),
      lessThan(order.indexOf('customer_invoice_items')),
    );
  });
}
