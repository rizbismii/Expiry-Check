import 'package:expiry_check/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Product make({required DateTime expiry}) => Product(
        name: 'Milk',
        brand: 'DairyCo',
        batch: 'B123',
        expiryDate: expiry,
        addedDate: DateTime.now(),
      );

  group('Product status', () {
    test('expired product', () {
      final p = make(expiry: DateTime.now().subtract(const Duration(days: 2)));
      expect(p.isExpired, isTrue);
      expect(p.statusLabel, 'Expired');
    });

    test('expires today', () {
      final p = make(expiry: DateTime.now());
      expect(p.daysLeft, 0);
      expect(p.isExpired, isFalse);
      expect(p.statusLabel, 'Expires today');
    });

    test('expiring soon', () {
      final p = make(expiry: DateTime.now().add(const Duration(days: 10)));
      expect(p.isExpiringSoon, isTrue);
      expect(p.statusLabel, 'Expiring soon');
    });

    test('fresh', () {
      final p = make(expiry: DateTime.now().add(const Duration(days: 90)));
      expect(p.isExpired, isFalse);
      expect(p.isExpiringSoon, isFalse);
      expect(p.statusLabel, 'Fresh');
    });
  });

  group('Serialization', () {
    test('round-trips through map', () {
      final p = Product(
        id: 7,
        storeId: 2,
        name: 'Shampoo',
        brand: 'CleanCo',
        batch: 'LOT99',
        category: 'Salt Liquids',
        quantity: 3,
        expiryDate: DateTime(2027, 3, 15),
        addedDate: DateTime(2026, 7, 1),
        notes: 'bathroom shelf',
      );
      final restored = Product.fromMap(p.toMap());
      expect(restored.id, 7);
      expect(restored.storeId, 2);
      expect(restored.name, 'Shampoo');
      expect(restored.brand, 'CleanCo');
      expect(restored.batch, 'LOT99');
      expect(restored.category, 'Salt Liquids');
      expect(restored.quantity, 3);
      expect(restored.expiryDate, DateTime(2027, 3, 15));
      expect(restored.notes, 'bathroom shelf');
    });

    test('storeId defaults to 1 for legacy maps', () {
      final map = Product(
        name: 'Old item',
        expiryDate: DateTime(2027, 1, 1),
        addedDate: DateTime(2026, 1, 1),
      ).toMap()
        ..remove('storeId');
      expect(Product.fromMap(map).storeId, 1);
    });
  });
}
