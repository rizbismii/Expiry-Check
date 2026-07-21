import 'package:expiry_check/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Product remote mapping', () {
    test('round-trips through remote map', () {
      final local = Product(
        cloudId: '11111111-1111-1111-1111-111111111111',
        storeId: 2,
        name: 'Berry',
        brand: 'SALTY PUFF WORLD',
        barcodeId: '6937035203622',
        batch: 'ALY32250319',
        category: 'Salt Liquids',
        quantity: 3,
        prodDate: DateTime(2025, 3, 19),
        expiryDate: DateTime(2027, 3, 18),
        addedDate: DateTime(2026, 7, 1, 10),
        updatedAt: DateTime(2026, 7, 2, 12),
        notes: 'shelf A',
        createdBy: 'admin',
      );

      final remote = local.toRemoteMap('user-abc');
      expect(remote['id'], local.cloudId);
      expect(remote['user_id'], 'user-abc');
      expect(remote['store_id'], 2);
      expect(remote['barcode_id'], '6937035203622');
      expect(remote['deleted_at'], isNull);

      final restored = Product.fromRemoteMap(remote);
      expect(restored.cloudId, local.cloudId);
      expect(restored.storeId, 2);
      expect(restored.name, 'Berry');
      expect(restored.brand, 'SALTY PUFF WORLD');
      expect(restored.barcodeId, '6937035203622');
      expect(restored.batch, 'ALY32250319');
      expect(restored.quantity, 3);
      expect(restored.prodDate?.year, 2025);
      expect(restored.expiryDate.year, 2027);
      expect(restored.createdBy, 'admin');
    });

    test('fromMap tolerates legacy rows without cloudId/updatedAt', () {
      final map = {
        'id': 1,
        'storeId': 1,
        'name': 'Old',
        'brand': '',
        'barcodeId': '',
        'batch': '',
        'category': 'General',
        'quantity': 1,
        'expiryDate': '2027-01-01T00:00:00.000',
        'addedDate': '2026-01-01T00:00:00.000',
        'notes': '',
        'createdBy': '',
      };
      final p = Product.fromMap(map);
      expect(p.cloudId, '');
      expect(p.updatedAt, DateTime.parse('2026-01-01T00:00:00.000'));
    });
  });
}
