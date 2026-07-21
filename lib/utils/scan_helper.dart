import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../services/database_service.dart';
import '../services/ocr_service.dart';
import '../utils/date_parser.dart';
import '../utils/text_similarity.dart';

/// Guides the user through capturing up to [maxShots] photos of a product
/// (front for brand/flavour, bottom/side for barcode, prod/expiry & batch),
/// optionally cropping each shot, running on-device OCR, and parsing the
/// combined text. Brand guesses are auto-corrected against known inventory.
///
/// Returns null when the user cancels before taking any photo.
Future<OcrParseResult?> captureAndRecognize(BuildContext context,
    {int maxShots = 3}) async {
  final picker = ImagePicker();
  final texts = <String>[];

  for (var shot = 1; shot <= maxShots; shot++) {
    String? path;
    while (path == null) {
      // Full resolution helps ML Kit read small inkjet PRO/EXP/batch lines.
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
        maxWidth: 4096,
        maxHeight: 4096,
      );
      if (photo == null) {
        // Cancelled camera — finish with whatever we have so far.
        path = '';
        break;
      }
      if (!context.mounted) {
        path = '';
        break;
      }
      final cropped = await _maybeCrop(context, photo.path, shot: shot);
      if (cropped == null) {
        // Retake — loop and open camera again.
        continue;
      }
      path = cropped;
    }
    if (path == null || path.isEmpty) break;

    texts.add(await OcrService.instance.recognizeText(path));
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
    final corrected =
        TextSimilarity.bestBrandMatch(brand, known, threshold: 0.6);
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

/// Ask whether to crop; returns the path to use, or null if cancelled.
Future<String?> _maybeCrop(BuildContext context, String sourcePath,
    {required int shot}) async {
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(shot == 1 ? 'Crop label?' : 'Crop photo $shot?'),
      content: const Text(
        'Cropping to just the text (barcode, dates, brand) improves scan '
        'accuracy. Or use the full photo as taken.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('Retake'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'full'),
          child: const Text('Use full photo'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, 'crop'),
          icon: const Icon(Icons.crop),
          label: const Text('Crop'),
        ),
      ],
    ),
  );

  if (choice == null || choice == 'cancel') return null;
  if (choice == 'full') return sourcePath;

  final cropped = await ImageCropper().cropImage(
    sourcePath: sourcePath,
    compressQuality: 100,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Crop label',
        toolbarColor: const Color(0xFF1B5E20),
        toolbarWidgetColor: Colors.white,
        activeControlsWidgetColor: const Color(0xFF1B5E20),
        initAspectRatio: CropAspectRatioPreset.original,
        lockAspectRatio: false,
        hideBottomControls: false,
      ),
      IOSUiSettings(
        title: 'Crop label',
        doneButtonTitle: 'Done',
        cancelButtonTitle: 'Cancel',
      ),
    ],
  );
  // Cancelled crop → fall back to full photo so the scan is not lost.
  return cropped?.path ?? sourcePath;
}
