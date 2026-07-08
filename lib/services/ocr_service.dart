import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../utils/date_parser.dart';

/// Runs Google ML Kit on-device text recognition on a captured photo and
/// parses out expiry date, batch number and a brand guess. Fully offline and
/// free — no cloud vision API costs.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  Future<OcrParseResult> scanImage(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFile(File(imagePath));
      final recognized = await recognizer.processImage(input);
      return DateParser.parse(recognized.text);
    } finally {
      await recognizer.close();
    }
  }
}
