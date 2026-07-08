import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _weekdays = {
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  };

  int _weekday = DateTime.monday;
  int _hour = 9;
  int _leadDays = 7;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = NotificationService.instance;
    final weekday = await service.getWeeklyWeekday();
    final hour = await service.getWeeklyHour();
    final leadDays = await service.getLeadDays();
    if (!mounted) return;
    setState(() {
      _weekday = weekday;
      _hour = hour;
      _leadDays = leadDays;
      _loading = false;
    });
  }

  Future<void> _saveNotificationSettings() async {
    await NotificationService.instance.saveSettings(
      weekday: _weekday,
      hour: _hour,
      leadDays: _leadDays,
    );
    _snack('Notification schedule updated.');
  }

  Future<void> _exportExcel() => _run(() async {
        final products = await DatabaseService.instance.getAll();
        if (products.isEmpty) {
          _snack('No products to export yet.');
          return;
        }
        await ExportService.instance.shareExcelReport(products);
      });

  Future<void> _backup() => _run(() async {
        final products = await DatabaseService.instance.getAll();
        if (products.isEmpty) {
          _snack('No products to back up yet.');
          return;
        }
        await ExportService.instance.shareJsonBackup(products);
      });

  Future<void> _restore() => _run(() async {
        final picked = await FilePicker.pickFiles(
          type: FileType.any,
          withData: false,
        );
        final path = picked?.files.single.path;
        if (path == null) return;
        final content = await File(path).readAsString();
        final products = ExportService.instance.parseBackup(content);

        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Restore backup?'),
            content: Text(
                'This will replace your current inventory with '
                '${products.length} product(s) from the backup file.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Restore')),
            ],
          ),
        );
        if (confirmed != true) return;

        await DatabaseService.instance.replaceAll(products);
        await NotificationService.instance.rescheduleAll();
        _snack('Restored ${products.length} product(s).');
      });

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack('Operation failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionTitle('Weekly notifications'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.calendar_view_week),
                        title: const Text('Digest day'),
                        trailing: DropdownButton<int>(
                          value: _weekday,
                          underline: const SizedBox.shrink(),
                          items: _weekdays.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _weekday = v ?? _weekday),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.access_time),
                        title: const Text('Notification time'),
                        trailing: DropdownButton<int>(
                          value: _hour,
                          underline: const SizedBox.shrink(),
                          items: List.generate(24, (h) => h)
                              .map((h) => DropdownMenuItem(
                                  value: h,
                                  child: Text(
                                      '${h.toString().padLeft(2, '0')}:00')))
                              .toList(),
                          onChanged: (v) => setState(() => _hour = v ?? _hour),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.notification_important),
                        title: const Text('Remind before expiry'),
                        trailing: DropdownButton<int>(
                          value: _leadDays,
                          underline: const SizedBox.shrink(),
                          items: const [3, 7, 14, 30]
                              .map((d) => DropdownMenuItem(
                                  value: d, child: Text('$d days')))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _leadDays = v ?? _leadDays),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: FilledButton.icon(
                          onPressed: _saveNotificationSettings,
                          icon: const Icon(Icons.check),
                          label: const Text('Apply schedule'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('Reports'),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.table_view),
                    title: const Text('Export Excel report'),
                    subtitle: const Text(
                        'Full inventory with brand, batch, expiry and status'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : _exportExcel,
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('Backup & restore'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.cloud_upload_outlined),
                        title: const Text('Back up data'),
                        subtitle: const Text(
                            'Share a backup file to Google Drive, iCloud or email — uses your existing free cloud storage'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : _backup,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.cloud_download_outlined),
                        title: const Text('Restore from backup'),
                        subtitle:
                            const Text('Import a previously exported file'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : _restore,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('About'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: const [
                      ListTile(
                        leading: Icon(Icons.privacy_tip_outlined),
                        title: Text('Your data stays on your device'),
                        subtitle: Text(
                            'Products are stored locally (SQLite) and AI text recognition runs fully offline with ML Kit — no servers, no subscription costs.'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
