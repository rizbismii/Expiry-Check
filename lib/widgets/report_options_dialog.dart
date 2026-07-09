import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/export_service.dart';
import '../utils/date_parser.dart';

/// Lets the user choose what an Excel report is based on (expiry date or
/// added date) and an optional dd/mm/yyyy date range, typeable or picked
/// from a calendar. Returns null when cancelled.
Future<ReportOptions?> showReportOptionsDialog(BuildContext context) {
  return showDialog<ReportOptions>(
    context: context,
    builder: (context) => const _ReportOptionsDialog(),
  );
}

class _ReportOptionsDialog extends StatefulWidget {
  const _ReportOptionsDialog();

  @override
  State<_ReportOptionsDialog> createState() => _ReportOptionsDialogState();
}

class _ReportOptionsDialogState extends State<_ReportOptionsDialog> {
  static final _nzDateFmt = DateFormat('dd/MM/yyyy');

  final _formKey = GlobalKey<FormState>();
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  ReportBasis _basis = ReportBasis.expiryDate;

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  String? _validateOptionalDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (DateParser.parseTypedDate(value) == null) {
      return 'Use dd/mm/yyyy';
    }
    return null;
  }

  Future<void> _pickInto(TextEditingController controller) async {
    final now = DateTime.now();
    final current = DateParser.parseTypedDate(controller.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) {
      setState(() => controller.text = _nzDateFmt.format(picked));
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final from = DateParser.parseTypedDate(_fromCtrl.text);
    final to = DateParser.parseTypedDate(_toCtrl.text);
    if (from != null && to != null && to.isBefore(from)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('"To" date must be after the "From" date.')));
      return;
    }
    Navigator.pop(context, ReportOptions(basis: _basis, from: from, to: to));
  }

  Widget _dateField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'dd/mm/yyyy',
        suffixIcon: IconButton(
          tooltip: 'Pick from calendar',
          icon: const Icon(Icons.calendar_month),
          onPressed: () => _pickInto(controller),
        ),
      ),
      keyboardType: TextInputType.datetime,
      validator: _validateOptionalDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Excel report options'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Report based on'),
              RadioListTile<ReportBasis>(
                value: ReportBasis.expiryDate,
                groupValue: _basis,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Expiry date'),
                onChanged: (v) => setState(() => _basis = v!),
              ),
              RadioListTile<ReportBasis>(
                value: ReportBasis.addedDate,
                groupValue: _basis,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Added date'),
                onChanged: (v) => setState(() => _basis = v!),
              ),
              const SizedBox(height: 8),
              const Text('Date range (optional — leave blank for all)'),
              const SizedBox(height: 8),
              _dateField(_fromCtrl, 'From'),
              const SizedBox(height: 12),
              _dateField(_toCtrl, 'To'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.table_view),
          label: const Text('Export'),
        ),
      ],
    );
  }
}
