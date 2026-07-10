import 'package:flutter/services.dart';

/// Batch/lot numbers are always stored in capitals with no spaces, so
/// "Aly 32 260424" becomes "ALY32260424" as it is typed.
class BatchInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Same normalization for programmatic values (OCR prefill, dictation).
  static String normalize(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'\s+'), '');
}
