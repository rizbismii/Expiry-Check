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

    final more = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Photo $shot scanned'),
        content: Text(shot == 1
            ? 'Scan the bottom/back panel too — barcode, prod date, expiry '
                'and batch are usually printed there (often as dotted inkjet '
                'text under the barcode).'
            : 'Add one more photo? (${maxShots - shot} left)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Done'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.add_a_photo),
            label: Text('Photo ${shot + 1} of $maxShots'),
          ),
        ],
      ),
    );
    if (more != true) break;
  }

  if (texts.isEmpty) return null;
  final result = DateParser.parse(texts.join('\n'));

  // Self-learning brand correction from the shop's existing inventory.
  var brand = result.brand;
  if (brand != null) {
    final known = await DatabaseService.instance.getKnownBrands();
    final corrected = TextSimilarity.bestBrandMatch(brand, known);
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
