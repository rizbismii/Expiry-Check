import 'dart:math';

/// Fuzzy text matching used to auto-correct OCR misreads (e.g. "GALTY"
/// recognized from a stylized "SALTY" logo) against names already stored in
/// the inventory.
class TextSimilarity {
  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    final current = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        current[j + 1] = min(
          min(current[j] + 1, previous[j + 1] + 1),
          previous[j] + cost,
        );
      }
      previous = List.of(current);
    }
    return previous[b.length];
  }

  /// 0–1 ratio between two raw strings after normalization.
  static double ratio(String a, String b) {
    final na = _norm(a);
    final nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return 0;
    final maxLen = max(na.length, nb.length);
    return 1 - levenshtein(na, nb) / maxLen;
  }

  /// Similarity tuned for brand matching: also compares the candidate to a
  /// same-length prefix of the known brand, since OCR often catches only the
  /// first word of a multi-word logo ("GALTY" vs "Salty Puff World").
  static double brandScore(String candidate, String known) {
    final c = _norm(candidate);
    final k = _norm(known);
    if (c.isEmpty || k.isEmpty) return 0;
    if (c == k) return 1;
    if (k.contains(c) || c.contains(k)) return 0.9;
    var best = 1 - levenshtein(c, k) / max(c.length, k.length);
    if (k.length > c.length) {
      final prefix = k.substring(0, c.length);
      best = max(best, 1 - levenshtein(c, prefix) / c.length);
    }
    return best;
  }

  /// Best match for [candidate] among [known], or null when nothing scores
  /// at least [threshold].
  static String? bestBrandMatch(String candidate, List<String> known,
      {double threshold = 0.7}) {
    String? best;
    var bestScore = threshold;
    for (final k in known) {
      final score = brandScore(candidate, k);
      if (score >= bestScore) {
        bestScore = score;
        best = k;
      }
    }
    return best;
  }
}
