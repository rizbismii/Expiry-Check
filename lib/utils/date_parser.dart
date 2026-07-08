/// Parses expiry dates, batch numbers and brand names from raw OCR text
/// captured from product packaging.
class OcrParseResult {
  final DateTime? expiryDate;
  final String? batch;
  final String? brand;
  final String rawText;

  const OcrParseResult({
    this.expiryDate,
    this.batch,
    this.brand,
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
    r'(mfg|mfd|manufactur|prod(uction|\.)?\s*date|pkd|packed)',
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

  /// Extracts expiry date, batch number and a brand-name guess from OCR text.
  static OcrParseResult parse(String text) {
    final lines = text
        .split(RegExp(r'[\n\r]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final candidates = <_DateCandidate>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Skip manufacture-date lines unless they also mention expiry.
      final isMfgLine =
          _mfgKeywords.hasMatch(line) && !_expiryKeywords.hasMatch(line);
      final nearExpiry = _expiryKeywords.hasMatch(line) ||
          (i > 0 && _expiryKeywords.hasMatch(lines[i - 1]));
      for (final date in _datesInLine(line)) {
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
    final batch = batchMatch?.group(1)?.toUpperCase();

    final brand = _guessBrand(lines);

    return OcrParseResult(
      expiryDate: expiry,
      batch: batch,
      brand: brand,
      rawText: text,
    );
  }

  static List<DateTime> _datesInLine(String line) {
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
      // Assume day-first (common on packaging); fall back to month-first.
      final d = _safeDate(year, b, a) ?? _safeDate(year, a, b);
      if (d != null) {
        results.add(d);
        consumed.add((m.start, m.end));
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

  static DateTime? _safeDate(int year, int month, int day) {
    if (year < 2000 || year > 2100) return null;
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

  static String? _guessBrand(List<String> lines) {
    for (final line in lines) {
      if (line.length < 2 || line.length > 40) continue;
      if (_expiryKeywords.hasMatch(line) ||
          _mfgKeywords.hasMatch(line) ||
          _batchPattern.hasMatch(line)) {
        continue;
      }
      // Lines that are mostly digits or symbols are unlikely to be a brand.
      final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (letters.length < line.length * 0.5) continue;
      return line;
    }
    return null;
  }
}

class _DateCandidate {
  final DateTime date;
  final bool nearExpiryKeyword;
  final bool onMfgLine;

  const _DateCandidate(this.date, this.nearExpiryKeyword, this.onMfgLine);
}
