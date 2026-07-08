import 'package:expiry_check/utils/date_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateParser expiry dates', () {
    test('parses EXP dd/mm/yyyy', () {
      final r = DateParser.parse('EXP: 15/08/2026');
      expect(r.expiryDate, DateTime(2026, 8, 15));
    });

    test('parses best before dd-mm-yy', () {
      final r = DateParser.parse('BEST BEFORE 03-12-27');
      expect(r.expiryDate, DateTime(2027, 12, 3));
    });

    test('parses month name format', () {
      final r = DateParser.parse('Expiry Date: 12 AUG 2026');
      expect(r.expiryDate, DateTime(2026, 8, 12));
    });

    test('parses month/year only as end of month', () {
      final r = DateParser.parse('EXP 08/2026');
      expect(r.expiryDate, DateTime(2026, 8, 31));
    });

    test('parses month-name/year only as end of month', () {
      final r = DateParser.parse('Use by: SEP 2026');
      expect(r.expiryDate, DateTime(2026, 9, 30));
    });

    test('parses yyyy-mm-dd', () {
      final r = DateParser.parse('EXP 2026-11-05');
      expect(r.expiryDate, DateTime(2026, 11, 5));
    });

    test('prefers expiry-keyword date over manufacture date', () {
      final r = DateParser.parse('MFG: 01/01/2025\nEXP: 01/01/2027');
      expect(r.expiryDate, DateTime(2027, 1, 1));
    });

    test('picks later date when both unlabeled', () {
      final r = DateParser.parse('01/01/2025  01/01/2027');
      expect(r.expiryDate, DateTime(2027, 1, 1));
    });

    test('uses keyword on previous line', () {
      final r = DateParser.parse('BEST BEFORE\n20/10/2026');
      expect(r.expiryDate, DateTime(2026, 10, 20));
    });

    test('returns null when no date present', () {
      final r = DateParser.parse('Chocolate Biscuits 200g');
      expect(r.expiryDate, isNull);
    });

    test('rejects invalid calendar dates', () {
      final r = DateParser.parse('EXP 31/02/2026');
      expect(r.expiryDate, isNull);
    });
  });

  group('DateParser batch numbers', () {
    test('parses Batch No', () {
      final r = DateParser.parse('Batch No: AB1234');
      expect(r.batch, 'AB1234');
    });

    test('parses LOT', () {
      final r = DateParser.parse('LOT 9X8Y7Z');
      expect(r.batch, '9X8Y7Z');
    });

    test('parses B.No with punctuation', () {
      final r = DateParser.parse('B.No. K-2201/A');
      expect(r.batch, 'K-2201/A');
    });

    test('returns null when absent', () {
      final r = DateParser.parse('EXP 12/2026');
      expect(r.batch, isNull);
    });
  });

  group('DateParser brand guess', () {
    test('picks first plausible text line', () {
      final r = DateParser.parse('Nestlé Milkpak\nEXP: 01/05/2027\nB.No 771');
      expect(r.brand, 'Nestlé Milkpak');
    });

    test('skips numeric-heavy lines', () {
      final r = DateParser.parse('8901234567890\nAmul Butter\nEXP 05/2027');
      expect(r.brand, 'Amul Butter');
    });
  });

  group('Combined label parsing', () {
    test('full label extracts all fields', () {
      const label = '''
Colgate MaxFresh
NET WT 150g
MFD: 02/2025
EXP: 01/2027
Batch No: CG44521
''';
      final r = DateParser.parse(label);
      expect(r.brand, 'Colgate MaxFresh');
      expect(r.expiryDate, DateTime(2027, 1, 31));
      expect(r.batch, 'CG44521');
    });
  });
}
