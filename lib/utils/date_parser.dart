/// Parses expiry dates, batch numbers, brand/product names, nicotine
/// strength and a category guess from raw OCR text captured from product
/// packaging.
class OcrParseResult {
  final DateTime? expiryDate;
  final DateTime? prodDate;
  final String? barcodeId;
  final String? batch;
  final String? brand;

  /// Flavour/product line combined with strength, e.g. "BERRY LEMON 11.4 mg/mL".
  final String? productName;
  final String? strength;
  final String? category;
  final String rawText;

  const OcrParseResult({
    this.expiryDate,
    this.prodDate,
    this.barcodeId,
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

  // Allow OCR noise: missing colon, "PR0", spaced "E XP".
  static final _expiryKeywords = RegExp(
    r'(exp(iry|ires|\.)?\s*(date)?|best\s*(before|by)|use\s*(by|before)|bbe?\b|'
    r'\be\s*x\s*p\b|\be\s*:)',
    caseSensitive: false,
  );

  static final _mfgKeywords = RegExp(
    r'(mfg|mfd|manufactur|prod(uction|\.)?\s*date|pkd|packed|\bpr[o0]\b)',
    caseSensitive: false,
  );

  /// Explicit PRO/EXP (and OCR variants) followed by a compact date.
  /// Digits may include O/I/l/S substitutions from weak inkjet OCR.
  /// Spaces/tabs only — never newlines, or PRO would swallow EXP digits.
  static final _labelledCompactDate = RegExp(
    r'\b(pr[o0]|mfg|mfd|exp|bbe?)\s*[:.\-]?\s*'
    r'([0-9OIlZSBgqo][0-9OIlZSBgqo \t]{5,15})',
    caseSensitive: false,
  );

  /// Looser label+digits when colon/spacing is mangled: "PRO19032025",
  /// "EXP18032027", "PR0 19O32O25".
  static final _labelledNoisyDate = RegExp(
    r'(?<![A-Za-z])(pr[o0]|exp|mfg|mfd)\s*[:.\-]?\s*([0-9OIlZSBgqo]{6,12})',
    caseSensitive: false,
  );

  /// Retail barcode printed under the bars, e.g. "6 937035 203622".
  static final _spacedBarcodeLine = RegExp(
    r'^\s*(\d)\s+(\d{5,6})\s+(\d{5,6})\s*$',
  );

  static final _batchPattern = RegExp(
    r'(?:batch\s*(?:no\.?|number|#)?|b\.?\s*no\.?|lot\s*(?:no\.?|number|#)?|l\.?\s*no\.?)\s*[:.\-#]?\s*([A-Za-z0-9][A-Za-z0-9\-\/]{1,19})',
    caseSensitive: false,
  );

  static final _barcodePattern = RegExp(
    r'(?:bar\s*code|barcode|ean|upc|gtin)\s*(?:id|no\.?|number|#)?\s*[:.\-#]?\s*([0-9][0-9\s\-]{6,20})',
    caseSensitive: false,
  );

  // Typical NZ vape batch printed under EXP: "ALY32 250319".
  static final _alyBatchPattern = RegExp(
    r'\b([A-Z]{2,5}\d{1,3})\s*([0-9]{6})\b',
    caseSensitive: false,
  );

  /// Built-in brands for NZ vape packs — used when inventory is empty and
  /// stylized logos only OCR as "SALTY" / "WORLD".
  static const knownVapeBrands = [
    'SALTY PUFF WORLD',
    'SALTY FIZZY WORLD',
    'SALTY WORLD',
  ];

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
  // Spaced compact dates from weak OCR: "19 03 2025" / "19 032025".
  static final _spacedCompactDate = RegExp(
    r'\b(\d{2})\s+(\d{2})\s+(\d{4})\b|\b(\d{2})\s+(\d{6})\b',
  );

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
    r'ingredients|store\s+in|made\s+in|18\s*\+|sub-?\s*ohm|\bseries\b|'
    r'\b\d+\s*ml\b|nicotine)',
    caseSensitive: false,
  );

  /// Common single-word flavour names used as the product line on vape packs.
  static const _flavourWords = {
    'berry',
    'lemon',
    'mint',
    'mango',
    'grape',
    'apple',
    'peach',
    'cherry',
    'banana',
    'melon',
    'watermelon',
    'strawberry',
    'blueberry',
    'raspberry',
    'cola',
    'coffee',
    'tobacco',
    'vanilla',
    'coconut',
    'pineapple',
    'orange',
    'lime',
    'kiwi',
    'guava',
    'lychee',
    'ice',
    'menthol',
    'cream',
    'custard',
  };

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
      for (final date in _datesInLine(
          line, lineHasExpiryKeyword || isMfgLine)) {
        candidates.add(_DateCandidate(date, nearExpiry, isMfgLine));
      }
    }

    // Explicit PRO:/EXP: dates — these win over any heuristic.
    DateTime? labelledExpiry;
    DateTime? labelledProd;
    for (final pattern in [_labelledCompactDate, _labelledNoisyDate]) {
      for (final m in pattern.allMatches(text)) {
        final label = m.group(1)!.toLowerCase().replaceAll('0', 'o');
        final digits = _ocrNormalizeDigits(m.group(2)!);
        // Take only the first 8 (or 6) digits after the label — never the
        // next line's digits if OCR glued lines together.
        final date = _parseCompactDigits(_firstCompactDigitRun(digits));
        if (date == null) continue;
        final isExp =
            label.startsWith('exp') || label == 'bb' || label == 'bbe';
        candidates.add(_DateCandidate(date, isExp, !isExp));
        if (isExp) {
          labelledExpiry ??= date;
        } else {
          labelledProd ??= date;
        }
      }
    }

    // Unlabeled compact dates are fallback only (never override PRO/EXP).
    for (final d in _noisyCompactDatesInText(text)) {
      candidates.add(_DateCandidate(d, false, false));
    }

    DateTime? expiry = labelledExpiry;
    DateTime? prodDate = labelledProd;

    if (expiry == null) {
      final keyworded = candidates.where((c) => c.nearExpiryKeyword).toList();
      final pool = keyworded.isNotEmpty
          ? keyworded
          : candidates.where((c) => !c.onMfgLine).toList();
      if (pool.isNotEmpty) {
        pool.sort((a, b) => b.date.compareTo(a.date));
        expiry = pool.first.date;
      }
    }

    if (prodDate == null) {
      final mfgDates = candidates.where((c) => c.onMfgLine).toList();
      if (mfgDates.isNotEmpty) {
        mfgDates.sort((a, b) => a.date.compareTo(b.date));
        prodDate = mfgDates.first.date;
      }
    }

    // Don't reuse the same calendar day as both prod and expiry.
    if (expiry != null && prodDate != null && _sameDay(prodDate, expiry)) {
      if (labelledExpiry != null && labelledProd == null) {
        prodDate = null;
      } else if (labelledProd != null && labelledExpiry == null) {
        expiry = null;
      } else if (labelledExpiry == null) {
        prodDate = null;
      }
    }

    // Bottom-panel fallback: two distinct compact dates, earlier = prod,
    // later = expiry — only fills fields still missing.
    if (expiry == null || prodDate == null) {
      final compactDates = <DateTime>[];
      for (final c in candidates) {
        // Skip unlabeled noise when we already have one labelled date.
        if (!c.nearExpiryKeyword &&
            !c.onMfgLine &&
            (labelledExpiry != null || labelledProd != null)) {
          continue;
        }
        compactDates.add(c.date);
      }
      for (final line in lines) {
        if (_licenceLine(line)) continue;
        if (_isBarcodeOnlyLine(line)) continue;
        for (final m in _compact8Pattern.allMatches(line)) {
          final d = _parseCompactDigits(m.group(1)!);
          if (d != null) compactDates.add(d);
        }
        for (final m in _spacedCompactDate.allMatches(line)) {
          final digits = m.group(0)!.replaceAll(RegExp(r'\s'), '');
          final d = _parseCompactDigits(digits);
          if (d != null) compactDates.add(d);
        }
      }
      compactDates.sort((a, b) => a.compareTo(b));
      final unique = <DateTime>[];
      for (final d in compactDates) {
        if (unique.isEmpty || !_sameDay(unique.last, d)) unique.add(d);
      }
      if (unique.length >= 2) {
        prodDate ??= unique.first;
        expiry ??= unique.last;
      } else if (unique.length == 1) {
        expiry ??= unique.first;
      }
    }

    // If both present but ordered backwards (OCR swapped PRO/EXP), swap.
    if (prodDate != null && expiry != null && prodDate.isAfter(expiry)) {
      final tmp = prodDate;
      prodDate = expiry;
      expiry = tmp;
    }

    final batchMatch = _batchPattern.firstMatch(text);
    var batch = batchMatch?.group(1)?.toUpperCase();
    batch ??= _alyBatch(lines);
    batch ??= _alyBatchNoisy(text);
    batch ??= _fallbackBatch(lines);

    final barcodeId = _findBarcode(text, lines);

    final strength = _findStrength(text);
    var names = _guessNames(lines);
    var brand = _correctKnownBrand(names.$1, text);
    var productName = names.$2 ?? _findFlavourInText(text);
    // If product still looks like a leftover logo token (WORLD), replace with
    // a flavour found elsewhere on the pack.
    if (productName != null &&
        !_flavourWords.contains(productName.toLowerCase().split(' ').first)) {
      final flavour = _findFlavourInText(text);
      if (flavour != null) productName = flavour;
    }
    if (productName != null && strength != null) {
      if (!productName.toLowerCase().contains('mg')) {
        productName = '$productName $strength';
      }
    } else if (productName == null && strength != null) {
      productName = strength;
    }

    return OcrParseResult(
      expiryDate: expiry,
      prodDate: prodDate,
      barcodeId: barcodeId,
      batch: batch,
      brand: brand,
      productName: productName,
      strength: strength,
      category: _guessCategory(text),
      rawText: text,
    );
  }

  /// Parses a manually typed NZ-format date (dd/mm/yyyy, also accepts
  /// dd-mm-yyyy, dd.mm.yyyy, 2-digit years, and compact digit-only input
  /// such as 19022027 or 190227).
  static DateTime? parseTypedDate(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[-. ]'), '/');
    // Compact input without separators: ddmmyyyy or ddmmyy.
    if (RegExp(r'^\d{8}$').hasMatch(cleaned)) {
      return _safeDate(
        int.parse(cleaned.substring(4, 8)),
        int.parse(cleaned.substring(2, 4)),
        int.parse(cleaned.substring(0, 2)),
        minYear: 1990,
      );
    }
    if (RegExp(r'^\d{6}$').hasMatch(cleaned)) {
      return _safeDate(
        2000 + int.parse(cleaned.substring(4, 6)),
        int.parse(cleaned.substring(2, 4)),
        int.parse(cleaned.substring(0, 2)),
        minYear: 1990,
      );
    }
    final parts = cleaned.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    var year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    return _safeDate(year, month, day, minYear: 1990);
  }

  static List<DateTime> _datesInLine(String line, bool hasDateKeyword) {
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
    for (final m in _spacedCompactDate.allMatches(line)) {
      if (overlaps(m.start, m.end)) continue;
      final digits = m.group(0)!.replaceAll(RegExp(r'\s'), '');
      final d = _parseCompactDigits(digits);
      if (d != null) {
        results.add(d);
        consumed.add((m.start, m.end));
      }
    }
    for (final m in _compact8Pattern.allMatches(line)) {
      if (overlaps(m.start, m.end)) continue;
      final d = _parseCompactDigits(m.group(1)!);
      if (d != null) {
        results.add(d);
        consumed.add((m.start, m.end));
      }
    }
    if (hasDateKeyword) {
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

  static DateTime? _parseCompactDigits(String digits) {
    if (digits.length == 8) {
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
      return d;
    }
    if (digits.length == 6) {
      return _safeDate(
        _normalizeYear(int.parse(digits.substring(4, 6))),
        int.parse(digits.substring(2, 4)),
        int.parse(digits.substring(0, 2)),
      );
    }
    return null;
  }

  /// Map common OCR letter/digit confusions then strip non-digits.
  static String _ocrNormalizeDigits(String raw) {
    final buf = StringBuffer();
    for (final ch in raw.toUpperCase().split('')) {
      switch (ch) {
        case 'O':
        case 'Q':
        case 'D':
          buf.write('0');
        case 'I':
        case 'L':
        case '|':
          buf.write('1');
        case 'Z':
          buf.write('2');
        case 'S':
          buf.write('5');
        case 'B':
          buf.write('8');
        case 'G':
          buf.write('6');
        default:
          if (RegExp(r'[0-9]').hasMatch(ch)) buf.write(ch);
      }
    }
    return buf.toString();
  }

  static List<DateTime> _noisyCompactDatesInText(String text) {
    final out = <DateTime>[];
    for (final line in text.split(RegExp(r'[\n\r]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || _licenceLine(trimmed)) continue;
      final hasKeyword =
          _expiryKeywords.hasMatch(trimmed) || _mfgKeywords.hasMatch(trimmed);
      final digits = _ocrNormalizeDigits(trimmed);
      // Only mine digit windows from keyword lines or short digit-heavy lines
      // (avoids sliding across the barcode number).
      final shortDigitLine = digits.length >= 6 &&
          digits.length <= 14 &&
          trimmed.length <= 28;
      if (!hasKeyword && !shortDigitLine) continue;
      if (digits.length == 6 || digits.length == 8) {
        final d = _parseCompactDigits(digits);
        if (d != null) out.add(d);
        continue;
      }
      if (hasKeyword) {
        for (var i = 0; i + 8 <= digits.length; i++) {
          final d = _parseCompactDigits(digits.substring(i, i + 8));
          if (d != null) out.add(d);
        }
        for (var i = 0; i + 6 <= digits.length; i++) {
          final d = _parseCompactDigits(digits.substring(i, i + 6));
          if (d != null) out.add(d);
        }
      }
    }
    return out;
  }

  /// Expand partial OCR brand tokens using pack context + built-in brands.
  static String? _correctKnownBrand(String? candidate, String text) {
    final upper = text.toUpperCase();
    final hasPuff = upper.contains('PUFF') ||
        RegExp(r'\bP[IU]FF\b').hasMatch(upper) ||
        upper.contains('SUB-OHM') ||
        upper.contains('SUB OHM');
    final hasFizzy = upper.contains('FIZZY') || upper.contains('FIZZ');
    final hasSalty = upper.contains('SALTY') ||
        upper.contains('GALTY') ||
        upper.contains('5ALTY') ||
        (candidate != null &&
            RegExp(r'salty|galty|5alty', caseSensitive: false)
                .hasMatch(candidate));
    final hasWorld = upper.contains('WORLD') ||
        (candidate != null &&
            candidate.toUpperCase().contains('WORLD'));

    if (hasSalty && hasPuff) return 'SALTY PUFF WORLD';
    if (hasSalty && hasFizzy) return 'SALTY FIZZY WORLD';
    if (hasSalty && hasWorld) {
      // Default the common Sub-Ohm salt line when PUFF was missed by OCR.
      if (upper.contains('SALT') || upper.contains('MG')) {
        return 'SALTY PUFF WORLD';
      }
      return 'SALTY WORLD';
    }
    if (candidate == null || candidate.trim().isEmpty) {
      if (hasSalty) return 'SALTY PUFF WORLD';
      return null;
    }

    // Fuzzy against built-in brands.
    String? best;
    var bestScore = 0.65;
    final c = candidate.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final known in knownVapeBrands) {
      final k = known.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (k.contains(c) || c.contains(k)) {
        return known;
      }
      // Prefix match for "SALTY" vs "SALTYPUFFWORLD".
      final n = c.length < k.length ? c.length : k.length;
      if (n >= 4) {
        var same = 0;
        for (var i = 0; i < n; i++) {
          if (c[i] == k[i]) same++;
        }
        final score = same / k.length + (k.startsWith(c) ? 0.4 : 0);
        if (score >= bestScore) {
          bestScore = score;
          best = known;
        }
      }
    }
    return best ?? candidate;
  }

  static String? _findFlavourInText(String text) {
    final words = text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    final found = <String>[];
    for (final w in words) {
      if (_flavourWords.contains(w.toLowerCase())) {
        // Skip standalone ICE when it's part of "ICE EDITION".
        if (w == 'ICE') continue;
        found.add(w);
      }
    }
    if (found.isEmpty) return null;
    // Prefer distinctive flavours over generic "CREAM"/"ICE".
    found.sort((a, b) {
      int rank(String s) =>
          (s == 'CREAM' || s == 'MENTHOL') ? 1 : 0;
      return rank(a).compareTo(rank(b));
    });
    // Berry Lemon style: keep up to two adjacent flavour words if both present.
    if (found.length >= 2 &&
        text.toUpperCase().contains('${found[0]} ${found[1]}')) {
      return '${found[0]} ${found[1]}';
    }
    return found.first;
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

  static bool _licenceLine(String line) =>
      RegExp(r'licen[cs]e', caseSensitive: false).hasMatch(line);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// First 8 or 6 digit compact-date run from a normalized digit string.
  static String _firstCompactDigitRun(String digits) {
    if (digits.length >= 8) return digits.substring(0, 8);
    if (digits.length >= 6) return digits.substring(0, 6);
    return digits;
  }

  static bool _isBarcodeOnlyLine(String line) {
    final spaced = _spacedBarcodeLine.firstMatch(line);
    if (spaced != null) return true;
    final digits = _ocrNormalizeDigits(line);
    final nonSpace = line.replaceAll(RegExp(r'\s'), '');
    final mostlyDigits = nonSpace.isNotEmpty &&
        RegExp(r'^[0-9OIlZSBgqo|]+$', caseSensitive: false).hasMatch(nonSpace);
    return mostlyDigits && _isPlausibleBarcode(digits);
  }

  /// Labelled barcode / EAN / UPC, including spaced digits printed under the
  /// bars (e.g. "6 937035 203622"). Never slices digits out of the whole OCR
  /// blob (that mixed dates + licence into fake barcodes).
  static String? _findBarcode(String text, List<String> lines) {
    final labelled = _barcodePattern.firstMatch(text);
    if (labelled != null) {
      final digits = _ocrNormalizeDigits(labelled.group(1)!);
      if (_isPlausibleBarcode(digits)) return digits;
    }

    // Dedupe — OCR often repeats the same line via blocks/elements.
    final uniqueLines = <String>[];
    final seen = <String>{};
    for (final line in lines) {
      final key = line.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      uniqueLines.add(line.trim());
    }

    String? best;
    var bestScore = -1;
    for (var i = 0; i < uniqueLines.length; i++) {
      final line = uniqueLines[i];
      if (_expiryKeywords.hasMatch(line) ||
          _mfgKeywords.hasMatch(line) ||
          _batchPattern.hasMatch(line) ||
          _licenceLine(line) ||
          _alyBatchPattern.hasMatch(line)) {
        continue;
      }

      String? digits;
      var score = 0;

      final spaced = _spacedBarcodeLine.firstMatch(line);
      if (spaced != null) {
        digits = '${spaced.group(1)}${spaced.group(2)}${spaced.group(3)}';
        score += 50; // classic under-bars layout
      } else {
        final normalized = _ocrNormalizeDigits(line);
        final nonSpace = line.replaceAll(RegExp(r'\s'), '');
        final mostlyDigits = nonSpace.isNotEmpty &&
            RegExp(r'^[0-9OIlZSBgqo|]+$', caseSensitive: false)
                .hasMatch(nonSpace);
        if (mostlyDigits && _isPlausibleBarcode(normalized)) {
          digits = normalized;
          score += 20;
        } else {
          final m = RegExp(r'\b(\d{12,14})\b').firstMatch(line);
          if (m != null) {
            digits = m.group(1);
            score += 10;
          }
        }
      }

      if (digits == null || !_isPlausibleBarcode(digits)) continue;
      if (_looksLikeCompactDate(digits)) continue;
      // Manufacture licence numbers are typically 10 digits.
      if (digits.length == 10) continue;

      if (digits.length == 13) score += 15;
      if (digits.length == 12) score += 10;
      if (_hasValidEanCheckDigit(digits)) score += 25;

      // Prefer the digit line that sits just above PRO/EXP on the panel.
      final nearDate = [i + 1, i + 2, i - 1].any((j) =>
          j >= 0 &&
          j < uniqueLines.length &&
          (_expiryKeywords.hasMatch(uniqueLines[j]) ||
              _mfgKeywords.hasMatch(uniqueLines[j])));
      if (nearDate) score += 20;

      if (score > bestScore) {
        bestScore = score;
        best = digits;
      }
    }
    return best;
  }

  /// Retail barcodes are 12–14 digits. 8-digit values are almost always dates.
  static bool _isPlausibleBarcode(String digits) =>
      digits.length == 12 || digits.length == 13 || digits.length == 14;

  static bool _looksLikeCompactDate(String digits) {
    if (digits.length == 8) return _parseCompactDigits(digits) != null;
    // 13-digit barcodes can contain 8-digit date-like substrings — only
    // reject when the *whole* value is an 8-digit date.
    return false;
  }

  /// GS1 check digit for UPC-A (12) / EAN-13 (13). Returns false for other
  /// lengths so they can still win on layout score alone.
  static bool _hasValidEanCheckDigit(String digits) {
    if (digits.length != 12 && digits.length != 13) return false;
    var sum = 0;
    for (var i = 0; i < digits.length - 1; i++) {
      final n = int.parse(digits[i]);
      final fromRight = digits.length - 1 - i;
      sum += fromRight.isOdd ? n * 3 : n;
    }
    final check = (10 - (sum % 10)) % 10;
    return check == int.parse(digits[digits.length - 1]);
  }

  static String? _alyBatch(List<String> lines) {
    for (final line in lines) {
      if (_licenceLine(line)) continue;
      final m = _alyBatchPattern.firstMatch(line);
      if (m == null) continue;
      // Prefer lines near date/barcode panels.
      return '${m.group(1)!.toUpperCase()}${m.group(2)}';
    }
    return null;
  }

  /// Recover ALY## + YYMMDD / DDMMYY batches from inkjet OCR garbage
  /// (e.g. "ALVSO319" ≈ "ALY32 250319").
  static String? _alyBatchNoisy(String text) {
    // Direct clean match anywhere in the blob.
    final clean = _alyBatchPattern.firstMatch(text.toUpperCase());
    if (clean != null) {
      return '${clean.group(1)!.toUpperCase()}${clean.group(2)}';
    }

    // Letter-digit run near PRO/EXP lines.
    final aly = RegExp(
      r'\b(AL[YVWS][0-9OIlZS]{0,4})\s*([0-9OIlZSBgqo]{5,8})\b',
      caseSensitive: false,
    );
    for (final m in aly.allMatches(text)) {
      final head = m
          .group(1)!
          .toUpperCase()
          .replaceAll('V', 'Y')
          .replaceAll('W', 'Y')
          .replaceAll(RegExp(r'[^A-Z0-9]'), '');
      // Normalize head toward ALY##.
      var normalizedHead = head;
      if (normalizedHead.startsWith('AL') && normalizedHead.length >= 3) {
        if (normalizedHead[2] != 'Y') {
          normalizedHead = 'ALY${normalizedHead.substring(3)}';
        }
      }
      final digits = _ocrNormalizeDigits(m.group(2)!);
      if (digits.length < 6) continue;
      final tail = digits.length >= 6
          ? digits.substring(digits.length - 6)
          : digits;
      // Prefer heads that look like ALY + digits.
      final headDigits = _ocrNormalizeDigits(normalizedHead);
      final headLetters =
          normalizedHead.replaceAll(RegExp(r'[^A-Z]'), '');
      if (!headLetters.startsWith('AL')) continue;
      final numPart = headDigits.isEmpty ? '32' : headDigits;
      return 'ALY$numPart$tail';
    }
    return null;
  }

  /// Codes like "ALY32 260513" printed on the same panel as EXP/PRO dates
  /// without a "Batch" label.
  static String? _fallbackBatch(List<String> lines) {
    final codeLine = RegExp(r'^[A-Z0-9][A-Z0-9 \-\/.]{3,24}$');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!codeLine.hasMatch(line)) continue;
      if (_expiryKeywords.hasMatch(line) ||
          _mfgKeywords.hasMatch(line) ||
          _licenceLine(line)) {
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
      if (nearDateLine) {
        return line.replaceAll(RegExp(r'\s+'), '');
      }
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

  /// Returns (brand, productName). Stylized logos are often OCR'd as one
  /// word per line ("SALTY" / "PUFF" / "WORLD"); those are joined into the
  /// brand, and a following flavour word ("BERRY") becomes the product.
  static (String?, String?) _guessNames(List<String> lines) {
    final candidates = <String>[];
    for (final line in lines) {
      if (_isPlausibleName(line)) candidates.add(line);
    }
    if (candidates.isEmpty) return (null, null);

    // Join leading single-token logo fragments into one brand.
    final brandParts = <String>[];
    var i = 0;
    while (i < candidates.length) {
      final line = candidates[i];
      final words = line.split(RegExp(r'\s+'));
      final isFlavour = words.length == 1 &&
          _flavourWords.contains(words.first.toLowerCase());
      if (brandParts.isNotEmpty && isFlavour) break;
      if (brandParts.isNotEmpty &&
          words.length == 1 &&
          brandParts.join(' ').split(RegExp(r'\s+')).length >= 3) {
        break;
      }
      // Stop joining once we already have a multi-word brand and the next
      // candidate is itself multi-word (likely the flavour line).
      if (brandParts.isNotEmpty &&
          brandParts.join(' ').contains(' ') &&
          words.length >= 2) {
        break;
      }
      brandParts.add(line);
      i++;
      // Cap brand join at 4 fragments.
      if (brandParts.length >= 4) break;
      // After a multi-word line, don't keep joining unless next is a short
      // brand fragment like "WORLD".
      if (words.length >= 2) break;
    }

    String? brand = brandParts.isEmpty ? null : brandParts.join(' ');
    String? product;
    if (i < candidates.length) {
      product = candidates[i];
    }

    // If brand ended up as a single short token and product looks like the
    // rest of the logo ("WORLD"), keep joining until a flavour appears.
    if (brand != null &&
        product != null &&
        !brand.contains(' ') &&
        product.split(RegExp(r'\s+')).length == 1 &&
        !_flavourWords.contains(product.toLowerCase()) &&
        i + 1 < candidates.length) {
      final next = candidates[i + 1];
      if (_flavourWords.contains(next.toLowerCase().split(' ').first)) {
        brand = '$brand $product';
        product = next;
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
        _noisePattern.hasMatch(line) ||
        _licenceLine(line)) {
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
