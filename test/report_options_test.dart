import 'package:expiry_check/models/product.dart';
import 'package:expiry_check/services/export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  Product make(String name,
          {required DateTime expiry, required DateTime added}) =>
      Product(name: name, expiryDate: expiry, addedDate: added);

  final a = make('A',
      expiry: DateTime(2026, 8, 1), added: DateTime(2026, 7, 1, 14, 30));
  final b = make('B',
      expiry: DateTime(2026, 12, 25), added: DateTime(2026, 7, 5));
  final c = make('C',
      expiry: DateTime(2027, 3, 10), added: DateTime(2026, 6, 20));
  final all = [b, c, a];

  group('ReportOptions.apply', () {
    test('no range keeps everything, sorted by expiry', () {
      const options = ReportOptions();
      expect(options.apply(all).map((p) => p.name), ['A', 'B', 'C']);
    });

    test('expiry date range filters inclusively', () {
      final options = ReportOptions(
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 12, 25),
      );
      expect(options.apply(all).map((p) => p.name), ['A', 'B']);
    });

    test('added date basis sorts and filters by added date', () {
      final options = ReportOptions(
        basis: ReportBasis.addedDate,
        from: DateTime(2026, 7, 1),
      );
      // C was added in June, so it is excluded; A's time-of-day is ignored.
      expect(options.apply(all).map((p) => p.name), ['A', 'B']);
    });

    test('open-ended "to" range', () {
      final options = ReportOptions(to: DateTime(2026, 9, 1));
      expect(options.apply(all).map((p) => p.name), ['A']);
    });
  });

  group('ReportOptions labels', () {
    final fmt = DateFormat('dd/MM/yyyy');

    test('basis label', () {
      expect(const ReportOptions().basisLabel, 'Expiry date');
      expect(const ReportOptions(basis: ReportBasis.addedDate).basisLabel,
          'Added date');
    });

    test('range label', () {
      expect(const ReportOptions().rangeLabel(fmt), 'All dates');
      expect(
          ReportOptions(from: DateTime(2026, 7, 1), to: DateTime(2026, 8, 31))
              .rangeLabel(fmt),
          '01/07/2026 – 31/08/2026');
    });
  });
}
