import 'dart:io';
import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/date_parser.dart';

/// Runs Google ML Kit on-device text recognition on a captured photo and
/// parses out expiry date, batch number and a brand guess. Fully offline and
/// free — no cloud vision API costs.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  Future<OcrParseResult> scanImage(String imagePath) async {
    return DateParser.parse(await recognizeText(imagePath));
  }

  /// Raw recognized text for one photo; callers can combine several photos
  /// (front + bottom panels) before parsing.
  ///
  /// Runs ML Kit on the original image and on a contrast-boosted grayscale
  /// copy (helps dotted inkjet PRO/EXP/batch lines), then returns the
  /// combined text so the parser can see both readings.
  Future<String> recognizeText(String imagePath) async {
    final texts = <String>[];
    texts.add(await _recognizeFile(imagePath));

    final enhanced = await _writeEnhancedCopy(imagePath);
    if (enhanced != null) {
      try {
        final boosted = await _recognizeFile(enhanced);
        if (boosted.trim().isNotEmpty) texts.add(boosted);
      } finally {
        try {
          await File(enhanced).delete();
        } catch (_) {}
      }
    }

    // Keep order stable but drop exact duplicates.
    final unique = <String>[];
    for (final t in texts) {
      final trimmed = t.trim();
      if (trimmed.isEmpty) continue;
      if (unique.any((u) => u == trimmed)) continue;
      unique.add(trimmed);
    }
    return unique.join('\n');
  }

  Future<String> _recognizeFile(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFile(File(imagePath));
      final recognized = await recognizer.processImage(input);
      return _textFromRecognized(recognized);
    } finally {
      await recognizer.close();
    }
  }

  /// Prefer structured lines (better word breaks than [RecognizedText.text]
  /// alone), and also append element-joined lines for logos split into glyphs.
  static String _textFromRecognized(RecognizedText recognized) {
    final lines = <String>[];
    final elementLines = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final t = line.text.trim();
        if (t.isNotEmpty) lines.add(t);
        final elems = line.elements.map((e) => e.text.trim()).where((e) => e.isNotEmpty);
        final joined = elems.join(' ').trim();
        if (joined.isNotEmpty) elementLines.add(joined);
      }
    }
    final parts = <String>[
      if (recognized.text.trim().isNotEmpty) recognized.text.trim(),
      ...lines,
      ...elementLines,
    ];
    return parts.join('\n');
  }

  /// Grayscale + contrast stretch + mild sharpen — improves ML Kit reads of
  /// faint inkjet PRO/EXP/batch text under barcodes.
  Future<String?> _writeEnhancedCopy(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Cap work size so enhancement stays fast on phones.
      final maxSide = 2000;
      img.Image work = decoded;
      final longest = math.max(decoded.width, decoded.height);
      if (longest > maxSide) {
        final scale = maxSide / longest;
        work = img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
          interpolation: img.Interpolation.linear,
        );
      }

      work = img.grayscale(work);
      work = img.contrast(work, 160) ?? work;
      work = img.adjustColor(work, contrast: 1.4, brightness: 1.08);

      final dir = await getTemporaryDirectory();
      final outPath = p.join(
        dir.path,
        'ocr_enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(outPath).writeAsBytes(img.encodeJpg(work, quality: 95));
      return outPath;
    } catch (_) {
      return null;
    }
  }
}
