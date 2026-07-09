/// Parses expiry dates, batch numbers, brand/product names, nicotine
/// strength and a category guess from raw OCR text captured from product
/// packaging.
class OcrParseResult {
  final DateTime? expiryDate;
  final String? batch;
  final String? brand;

  /// Flavour/product line combined with strength, e.g. "BERRY LEMON 11.4 mg/mL".
  final String? productName;
  final String? strength;
  final String? category;
  final String rawText;

  const OcrParseResult({
    this.expiryDate,
    this.batch,
    this.brand,
    this.productName,
    this.strength,
    this.category,
    this.rawText = '',
  });
}

class DateParser {
  static const _monthNames = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static final _expiryKeywords = RegExp(
    r'(exp(iry|ires|\.)?\s*(date)?|best\s*(before|by)|use\s*(by|before)|bbe?\b|e\s*:)',
    caseSensitive: false,
  );

  static final _mfgKeywords = RegExp(
    r'(mfg|mfd|manufactur|prod(uction|\.)?\s*date|pkd|packed|\bpro\s*[:.])',
    caseSensitive: false,
  );

  static final _batchPattern = RegExp(
    r'(?:batch\s*(?:no\.?|number|#)?|b\.?\s*no\.?|lot\s*(?:no\.?|number|#)?|l\.?\s*no\.?)\s*[:.\-#]?\s*([A-Za-z0-9][A-Za-z0-9\-\/]{1,19})',
    caseSensitive: false,
  );

  // dd/mm/yyyy, dd-mm-yy, dd.mm.yyyy etc.
  static final _dmyPattern =
      RegExp(r'\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b');
  // yyyy-mm-dd
  static final _ymdPattern =
      RegExp(r'\b(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2})\b');
  // mm/yyyy or mm-yy
  static final _myPattern = RegExp(r'\b(\d{1,2})[\/\-.](\d{4}|\d{2})\b');
  // 12 AUG 2026, AUG 2026, 12AUG26
  static final _monthNamePattern = RegExp(
    r'\b(?:(\d{1,2})\s*[\-\/. ]?\s*)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*[\-\/. ,]?\s*(\d{2,4})\b',
    caseSensitive: false,
  );
  // Compact dates without separators: EXP: 12052028 (ddmmyyyy) or 20280512.
  static final _compact8Pattern = RegExp(r'\b(\d{8})\b');
  // Compact ddmmyy — ambiguous with codes, so only used on keyword lines.
  static final _compact6Pattern = RegExp(r'\b(\d{6})\b');

  // Nicotine/active-ingredient strength, e.g. "11.4 mg/mL", "50mg", "3%".
  static final _strengthPattern = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(mg\s*\/\s*ml|mg|%)',
    caseSensitive: false,
  );

  static final _urlPattern = RegExp(
    r'(www\.|https?:|\.com\b|\.co\b|\.nz\b|\.net\b|\.org\b)',
    caseSensitive: false,
  );

  // Warning/descriptor lines that are never a brand or product name.
  static final _noisePattern = RegExp(
    r'(contains|addictive|warning|caution|keep\s*(out|away)|children|net\s*wt|'
    r'licen[cs]e|concentration|e-?liquid|edition|substance|nikot|whakawara|'
    r'ingredients|store\s+in|made\s+in|18\s*\+)',
    caseSensitive: false,
  );

  /// Extracts all recognizable fields from OCR label text.
  static OcrParseResult parse(String text) {
    final lines = text
        .split(RegExp(r'[\n\r]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final candidates = <_DateCandidate>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineHasExpiryKeyword = _expiryKeywords.hasMatch(line);
      // Skip manufacture-date lines unless they also mention expiry.
      final isMfgLine = _mfgKeywords.hasMatch(line) && !lineHasExpiryKeyword;
      final nearExpiry = lineHasExpiryKeyword ||
          (i > 0 && _expiryKeywords.hasMatch(lines[i - 1]));
      for (final date in _datesInLine(line, lineHasExpiryKeyword)) {
        candidates.add(_DateCandidate(date, nearExpiry, isMfgLine));
      }
    }

    DateTime? expiry;
    if (candidates.isNotEmpty) {
      // Prefer dates flagged by expiry keywords, then the latest future date.
      final keyworded = candidates.where((c) => c.nearExpiryKeyword).toList();
      final pool = keyworded.isNotEmpty
          ? keyworded
          : candidates.where((c) => !c.onMfgLine).toList();
      final usable = pool.isNotEmpty ? pool : candidates;
      usable.sort((a, b) => b.date.compareTo(a.date));
      expiry = usable.first.date;
    }

    final batchMatch = _batchPattern.firstMatch(text);
    var batch = batchMatch?.group(1)?.toUpperCase();
    batch ??= _fallbackBatch(lines);

    final strength = _findStrength(text);
    final names = _guessNames(lines);
    final brand = names.$1;
    var productName = names.$2;
    if (productName != null && strength != null) {
      productName = '$productName $strength';
    }

    return OcrParseResult(
      expiryDate: expiry,
      batch: batch,
      brand: brand,
      productName: productName,
      strength: strength,
      category: _guessCategory(text),
      rawText: text,
    );
  }

  /// Parses a manually typed NZ-format date (dd/mm/yyyy, also accepts
  /// dd-mm-yyyy, dd.mm.yyyy and 2-digit years).
  static DateTime? parseTypedDate(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[-. ]'), '/');
    final parts = cleaned.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    var year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    return _safeDate(year, month, day, minYear: 1990);
  }

  static List<DateTime> _datesInLine(String line, bool hasExpiryKeyword) {
    final results = <DateTime>[];
    final consumed = <(int, int)>[];

    bool overlaps(int start, int end) =>
        consumed.any((r) => start < r.$2 && end > r.$1);

    for (final m in _ymdPattern.allMatches(line)) {
      final d = _safeDate(
          int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
      if (d != null) {
        results.add(d);
        consumed.add((m.start, m.end));
      }
    }
    for (final m in _dmyPattern.allMatches(line)) {
      if (overlaps(m.start, m.end)) continue;
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      final year = _normalizeYear(int.parse(m.group(3)!));
      // Assume day-first (NZ/packaging standard); fall back to month-first.
      final d = _safeDate(year, b, a) ?? _safeDate(year, a, b);
      if (d != null) {
        results.add(d);
        consumed.add((m.start, m.end));
      }
    }
    for (final m in _compact8Pattern.allMatches(line)) {
      if (overlaps(m.start, m.end)) continue;
      final digits = m.group(1)!;
      DateTime? d;
      // 20280512 style (year first) — only plausible when it starts with 20xx.
      if (digits.startsWith('20')) {
        d = _safeDate(
          int.parse(digits.substring(0, 4)),
          int.parse(digits.substring(4, 6)),
          int.parse(digits.substring(6, 8)),
        );
      }
      // 12052028 style (ddmmyyyy) as used on NZ vape/e-liquid packaging.
      d ??= _safeDate(
        int.parse(digits.substring(4, 8)),
        int.parse(digits.substring(2, 4)),
        int.parse(digits.substring(0, 2)),
      );
      if (d != null) {
        results.add(d);
        consumed.add((m.start, m.end));
      }
    }
    if (hasExpiryKeyword) {
      for (final m in _compact6Pattern.allMatches(line)) {
        if (overlaps(m.start, m.end)) continue;
        final digits = m.group(1)!;
        final d = _safeDate(
          _normalizeYear(int.parse(digits.substring(4, 6))),
          int.parse(digits.substring(2, 4)),
          int.parse(digits.substring(0, 2)),
        );
        if (d != null) {
          results.add(d);
          consumed.add((m.start, m.end));
        }
      }
    }
    for (final m in _monthNamePattern.allMatches(line)) {
      if (overlaps(m.start, m.end)) continue;
      final day = m.group(1) != null ? int.tryParse(m.group(1)!) : null;
      final month = _monthNames[m.group(2)!.toLowerCase().substring(0, 3)]!;
      final year = _normalizeYear(int.parse(m.group(3)!));
      final d = day != null
          ? _safeDate(year, month, day)
          : _endOfMonth(year, month);
      if (d != null) {
        results.add(d);
        consumed.add((m.start, m.end));
      }
    }
    for (final m in _myPattern.allMatches(line)) {
      if (overlaps(m.start, m.end)) continue;
      final month = int.parse(m.group(1)!);
      final year = _normalizeYear(int.parse(m.group(2)!));
      final d = _endOfMonth(year, month);
      if (d != null) results.add(d);
    }
    return results;
  }

  static int _normalizeYear(int year) {
    if (year >= 100) return year;
    return 2000 + year;
  }

  static DateTime? _safeDate(int year, int month, int day,
      {int minYear = 2000}) {
    if (year < minYear || year > 2100) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    final d = DateTime(year, month, day);
    // Reject rollovers such as 31 Feb -> 3 Mar.
    if (d.month != month || d.day != day) return null;
    return d;
  }

  static DateTime? _endOfMonth(int year, int month) {
    if (year < 2000 || year > 2100) return null;
    if (month < 1 || month > 12) return null;
    return DateTime(year, month + 1, 0);
  }

  /// Codes like "ALY32 260513" printed on the same panel as EXP/PRO dates
  /// without a "Batch" label.
  static String? _fallbackBatch(List<String> lines) {
    final codeLine = RegExp(r'^[A-Z0-9][A-Z0-9 \-\/.]{3,24}$');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!codeLine.hasMatch(line)) continue;
      if (_expiryKeywords.hasMatch(line) || _mfgKeywords.hasMatch(line)) {
        continue;
      }
      final letters = line.replaceAll(RegExp(r'[^A-Z]'), '').length;
      final digits = line.replaceAll(RegExp(r'[^0-9]'), '').length;
      if (letters < 2 || digits < 2) continue;
      // Must sit near a date line to avoid grabbing random codes.
      final nearDateLine = [i - 2, i - 1, i + 1, i + 2].any((j) =>
          j >= 0 &&
          j < lines.length &&
          (_expiryKeywords.hasMatch(lines[j]) ||
              _mfgKeywords.hasMatch(lines[j])));
      if (nearDateLine) return line;
    }
    return null;
  }

  static String? _findStrength(String text) {
    final m = _strengthPattern.firstMatch(text);
    if (m == null) return null;
    final value = m.group(1)!.replaceAll(',', '.');
    final unit = m.group(2)!.toLowerCase().replaceAll(RegExp(r'\s'), '');
    if (unit == '%') return '$value%';
    if (unit.startsWith('mg/')) return '$value mg/mL';
    return '$value mg';
  }

  /// Returns (brand, productName): the first plausible text line is treated
  /// as the brand, the next one as the product/flavour name.
  static (String?, String?) _guessNames(List<String> lines) {
    String? brand;
    String? product;
    for (final line in lines) {
      if (!_isPlausibleName(line)) continue;
      if (brand == null) {
        brand = line;
      } else if (line.toLowerCase() != brand.toLowerCase()) {
        product = line;
        break;
      }
    }
    return (brand, product);
  }

  static bool _isPlausibleName(String line) {
    if (line.length < 2 || line.length > 40) return false;
    if (_expiryKeywords.hasMatch(line) ||
        _mfgKeywords.hasMatch(line) ||
        _batchPattern.hasMatch(line) ||
        _urlPattern.hasMatch(line) ||
        _noisePattern.hasMatch(line)) {
      return false;
    }
    // Lines that are mostly digits or symbols are unlikely to be a name.
    final letters = line.replaceAll(RegExp(r'[^A-Za-zÀ-ž]'), '');
    return letters.length >= line.length * 0.5;
  }

  static String? _guessCategory(String text) {
    final t = text.toLowerCase();
    if (t.contains('shisha')) return 'Shisha Flavours';
    if (t.contains('detox')) return 'Detox Products';
    if (RegExp(r'free\s*-?\s*base').hasMatch(t)) return 'Free Base Liquids';
    if (t.contains('pod')) return 'Prefilled Vape Pods';
    if (t.contains('kit')) return 'Prefilled Kits';
    if (t.contains('salt')) return 'Salt Liquids';
    return null;
  }
}

class _DateCandidate {
  final DateTime date;
  final bool nearExpiryKeyword;
  final bool onMfgLine;

  const _DateCandidate(this.date, this.nearExpiryKeyword, this.onMfgLine);
}
