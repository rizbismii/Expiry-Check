import 'package:expiry_check/models/product.dart';
import 'package:expiry_check/models/store.dart';
import 'package:expiry_check/services/database_service.dart';
import 'package:expiry_check/services/notification_service.dart';
import 'package:expiry_check/utils/nz_date_input_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Duplicate-match normalization', () {
    test('ignores case differences', () {
      expect(DatabaseService.normalizeForMatch('SALTY Fizzy World'),
          DatabaseService.normalizeForMatch('salty fizzy world'));
    });

    test('ignores leading/trailing and repeated spaces', () {
      expect(DatabaseService.normalizeForMatch('  Berry   Lemon  '),
          DatabaseService.normalizeForMatch('Berry Lemon'));
    });

    test('different batches stay different', () {
      expect(
          DatabaseService.normalizeForMatch('ALY32 260513') ==
              DatabaseService.normalizeForMatch('ALY33 260513'),
          isFalse);
    });
  });

  group('NzDateInputFormatter', () {
    TextEditingValue format(String input) => NzDateInputFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: input));

    test('adds slashes automatically while typing digits', () {
      expect(format('1').text, '1');
      expect(format('12').text, '12');
      expect(format('120').text, '12/0');
      expect(format('1205').text, '12/05');
      expect(format('12052').text, '12/05/2');
      expect(format('12052028').text, '12/05/2028');
    });

    test('keeps manually typed slashes and strips other characters', () {
      expect(format('12/05/2028').text, '12/05/2028');
      expect(format('12-05-2028').text, '12/05/2028');
    });

    test('caps at 8 digits', () {
      expect(format('120520289').text, '12/05/2028');
    });
  });

  group('Weekly dashboard body', () {
    final stores = [
      const Store(id: 1, name: 'Queen Street'),
      const Store(id: 2, name: 'Dominion Road'),
    ];

    Product make(int storeId, int quantity, int daysFromNow) => Product(
          storeId: storeId,
          name: 'P',
          quantity: quantity,
          expiryDate: DateTime.now().add(Duration(days: daysFromNow)),
          addedDate: DateTime.now(),
        );

    test('sums quantities per band', () {
      final body = NotificationService.buildDashboardBody([
        make(1, 5, -2), // expired
        make(1, 3, 10), // <=30
        make(1, 2, 60), // <=90
        make(1, 7, 200), // fresh
      ], stores);
      expect(body, contains('Total stock: 17 units (4 products)'));
      expect(body, contains('Expired 5 • ≤30d 3 • ≤90d 2 • Fresh 7'));
      // Single branch: no per-store breakdown.
      expect(body.contains('Queen Street'), isFalse);
    });

    test('adds per-store lines when multiple branches hold stock', () {
      final body = NotificationService.buildDashboardBody([
        make(1, 4, 10),
        make(2, 6, 200),
      ], stores);
      expect(body, contains('Queen Street: 4 units'));
      expect(body, contains('Dominion Road: 6 units'));
    });

    test('empty inventory message', () {
      expect(NotificationService.buildDashboardBody([], stores),
          contains('No products tracked yet'));
    });
  });
}
