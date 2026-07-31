import 'package:flutter/material.dart';

import 'date_parser.dart';

/// Web stub — camera OCR is Android-only. Manual entry stays available.
Future<OcrParseResult?> captureAndRecognize(BuildContext context,
    {int maxShots = 3}) async {
  if (!context.mounted) return null;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text(
          'Camera scan is available in the Android app. '
          'On the web, please add products manually.',
        ),
      ),
    );
  return null;
}
