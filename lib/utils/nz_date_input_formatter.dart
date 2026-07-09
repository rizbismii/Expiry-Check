import 'package:flutter/services.dart';

/// Formats typed digits as a dd/mm/yyyy date, inserting the slashes
/// automatically so the field works with a plain numeric keyboard
/// (many Android keyboards hide '/' on the datetime layout).
/// Typing "12052028" produces "12/05/2028".
class NzDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(limited[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
