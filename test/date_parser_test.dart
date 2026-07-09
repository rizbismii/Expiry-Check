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

    test('parses compact ddmmyyyy (NZ vape packaging)', () {
      final r = DateParser.parse('EXP: 12052028');
      expect(r.expiryDate, DateTime(2028, 5, 12));
    });

    test('compact PRO date is treated as manufacture, not expiry', () {
      final r = DateParser.parse('PRO: 13052026\nEXP: 12052028');
      expect(r.expiryDate, DateTime(2028, 5, 12));
    });

    test('parses compact yyyymmdd', () {
      final r = DateParser.parse('EXP 20280512');
      expect(r.expiryDate, DateTime(2028, 5, 12));
    });

    test('parses compact ddmmyy on expiry keyword line', () {
      final r = DateParser.parse('EXP 120528');
      expect(r.expiryDate, DateTime(2028, 5, 12));
    });
  });

  group('DateParser.parseTypedDate (NZ manual input)', () {
    test('parses dd/mm/yyyy', () {
      expect(DateParser.parseTypedDate('12/05/2028'), DateTime(2028, 5, 12));
    });

    test('parses d/m/yy and other separators', () {
      expect(DateParser.parseTypedDate('3-8-26'), DateTime(2026, 8, 3));
      expect(DateParser.parseTypedDate('03.08.2026'), DateTime(2026, 8, 3));
    });

    test('rejects invalid input', () {
      expect(DateParser.parseTypedDate('31/02/2026'), isNull);
      expect(DateParser.parseTypedDate('12/2028'), isNull);
      expect(DateParser.parseTypedDate('hello'), isNull);
    });

    test('accepts compact digit-only input (no slashes)', () {
      expect(DateParser.parseTypedDate('19022027'), DateTime(2027, 2, 19));
      expect(DateParser.parseTypedDate('190227'), DateTime(2027, 2, 19));
      expect(DateParser.parseTypedDate('12052028'), DateTime(2028, 5, 12));
      expect(DateParser.parseTypedDate('99999999'), isNull);
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

    test('picks up unlabelled code next to EXP/PRO lines', () {
      final r = DateParser.parse('PRO: 13052026\nEXP: 12052028\nALY32 260513');
      expect(r.batch, 'ALY32 260513');
    });
  });

  group('DateParser strength and category', () {
    test('extracts mg/mL strength, even when OCR splits lines', () {
      final r = DateParser.parse('11.4\nmg/mL\nNicotine Concentration');
      expect(r.strength, '11.4 mg/mL');
      final r2 = DateParser.parse('11.4 mg/mL Nicotine Concentration');
      expect(r2.strength, '11.4 mg/mL');
    });

    test('extracts plain mg and percentage', () {
      expect(DateParser.parse('Nicotine 50mg').strength, '50 mg');
      expect(DateParser.parse('Nicotine 3% by volume').strength, '3%');
    });

    test('guesses category from label text', () {
      expect(DateParser.parse('NICOTINE SALT E-LIQUID').category,
          'Salt Liquids');
      expect(DateParser.parse('Premium Shisha Flavour').category,
          'Shisha Flavours');
      expect(DateParser.parse('FREEBASE E-LIQUID 70/30').category,
          'Free Base Liquids');
      expect(DateParser.parse('FREE BASE E-LIQUID 70/30').category,
          'Free Base Liquids');
      expect(DateParser.parse('Prefilled replacement pod 2ml').category,
          'Prefilled Vape Pods');
      expect(DateParser.parse('Starter kit with charger').category,
          'Prefilled Kits');
      expect(DateParser.parse('7-day detox drink').category,
          'Detox Products');
      expect(DateParser.parse('Plain biscuit').category, isNull);
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

    test('NZ nicotine salt e-liquid box (front + bottom panels)', () {
      // Mirrors the real label: Salty Fizzy World "Berry Lemon" 11.4 mg/mL.
      const label = '''
WWW.SALTYWORLD.CO
SALTY FIZZY WORLD
ICE EDITION
NICOTINE SALT E-LIQUID
BERRY LEMON
18+
11.4 mg/mL
Nicotine Concentration
THIS PRODUCT CONTAINS NICOTINE,
WHICH IS A HIGHLY ADDICTIVE SUBSTANCE
HE NIKOTINI KEI ROTO I TENEI MEA, HE
MATU TINO WHAKAWARA
8 19412 02557 6
PRO: 13052026
EXP: 12052028
ALY32 260513
Manufacture licence number: 4144030056
''';
      final r = DateParser.parse(label);
      expect(r.brand, 'SALTY FIZZY WORLD');
      expect(r.productName, 'BERRY LEMON 11.4 mg/mL');
      expect(r.strength, '11.4 mg/mL');
      expect(r.expiryDate, DateTime(2028, 5, 12));
      expect(r.batch, 'ALY32 260513');
      expect(r.category, 'Salt Liquids');
    });
  });
}
