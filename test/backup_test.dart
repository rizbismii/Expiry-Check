import 'dart:convert';

import 'package:expiry_check/models/product.dart';
import 'package:expiry_check/services/export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Backup parsing', () {
    test('parses v2 backup with stores', () {
      final payload = json.encode({
        'app': 'expiry_check',
        'version': 2,
        'stores': [
          {'id': 1, 'name': 'Queen Street'},
          {'id': 2, 'name': 'Dominion Road'},
        ],
        'products': [
          Product(
            storeId: 2,
            name: 'Berry Lemon 11.4 mg/mL',
            brand: 'Salty Fizzy World',
            batch: 'ALY32 260513',
            category: 'Salt Liquids',
            expiryDate: DateTime(2028, 5, 12),
            addedDate: DateTime(2026, 7, 9),
          ).toMap()
            ..remove('id'),
        ],
      });
      final backup = ExportService.instance.parseBackup(payload);
      expect(backup.stores, hasLength(2));
      expect(backup.stores[1].name, 'Dominion Road');
      expect(backup.products.single.storeId, 2);
      expect(backup.products.single.name, 'Berry Lemon 11.4 mg/mL');
    });

    test('parses legacy v1 backup without stores', () {
      final payload = json.encode({
        'app': 'expiry_check',
        'version': 1,
        'products': [
          {
            'name': 'Old item',
            'expiryDate': '2027-01-01T00:00:00.000',
            'addedDate': '2026-01-01T00:00:00.000',
          },
        ],
      });
      final backup = ExportService.instance.parseBackup(payload);
      expect(backup.stores, isEmpty);
      expect(backup.products.single.storeId, 1);
    });

    test('rejects foreign json', () {
      expect(() => ExportService.instance.parseBackup('{"foo": 1}'),
          throwsFormatException);
    });
  });
}
