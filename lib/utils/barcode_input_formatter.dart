import 'package:flutter/services.dart';

/// Barcode IDs are digits only — spacing from packaging OCR/voice like
/// "6 937035 203622" is stripped to "6937035203622".
class BarcodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = normalize(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Same normalization for OCR prefills, dictation, and save.
  static String normalize(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}
