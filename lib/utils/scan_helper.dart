import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/database_service.dart';
import '../services/ocr_service.dart';
import '../utils/date_parser.dart';
import '../utils/text_similarity.dart';

/// Guides the user through capturing up to [maxShots] photos of a product
/// (front for brand/flavour, bottom/side for barcode, prod/expiry & batch),
/// runs on-device text recognition on each, and parses the combined text. The
/// brand guess is auto-corrected against brands already in the inventory,
/// which fixes OCR misreads of stylized logos (e.g. "GALTY" -> "Salty Puff
/// World").
///
/// Returns null when the user cancels before taking any photo.
Future<OcrParseResult?> captureAndRecognize(BuildContext context,
    {int maxShots = 3}) async {
  final picker = ImagePicker();
  final texts = <String>[];

  for (var shot = 1; shot <= maxShots; shot++) {
    // Full resolution helps ML Kit read small inkjet PRO/EXP/batch lines.
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
      maxWidth: 4096,
      maxHeight: 4096,
    );
    if (photo == null) break;
    texts.add(await OcrService.instance.recognizeText(photo.path));
    if (shot == maxShots || !context.mounted) break;

    final partial = DateParser.parse(texts.join('\n'));
    final needsBottom = partial.expiryDate == null ||
        partial.barcodeId == null ||
        partial.prodDate == null;

    final more = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(needsBottom && shot == 1
            ? 'Bottom panel still needed'
            : 'Photo $shot scanned'),
        content: Text(shot == 1
            ? (needsBottom
                ? 'Front label is not enough for barcode, prod date and '
                    'expiry. Take a close photo of the bottom/back panel '
                    '(barcode + dotted PRO/EXP/batch lines).'
                : 'Optional: scan the bottom/back panel too for a clearer '
                    'barcode, prod date, expiry and batch.')
            : 'Add one more photo? (${maxShots - shot} left)'),
        actions: [
          if (!(needsBottom && shot == 1))
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Done'),
            ),
          if (needsBottom && shot == 1)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Continue anyway'),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.add_a_photo),
            label: Text(needsBottom && shot == 1
                ? 'Scan bottom panel'
                : 'Photo ${shot + 1} of $maxShots'),
          ),
        ],
      ),
    );
    if (more != true) break;
  }

  if (texts.isEmpty) return null;
  final result = DateParser.parse(texts.join('\n'));

  // Self-learning brand correction from the shop's existing inventory,
  // plus built-in Salty World brands.
  var brand = result.brand;
  final known = [
    ...DateParser.knownVapeBrands,
    ...await DatabaseService.instance.getKnownBrands(),
  ];
  if (brand != null) {
    final corrected = TextSimilarity.bestBrandMatch(brand, known, threshold: 0.6);
    if (corrected != null) brand = corrected;
  }

  return OcrParseResult(
    expiryDate: result.expiryDate,
    prodDate: result.prodDate,
    barcodeId: result.barcodeId,
    batch: result.batch,
    brand: brand,
    productName: result.productName,
    strength: result.strength,
    category: result.category,
    rawText: result.rawText,
  );
}
