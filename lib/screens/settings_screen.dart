import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/store.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../services/user_service.dart';
import '../widgets/report_options_dialog.dart';
import 'cloud_sync_screen.dart';
import 'login_screen.dart';
import 'users_screen.dart';

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
  String _frequency = 'weekly';
  int _dayOfMonth = 1;
  String _username = '';
  bool _isAdmin = false;
  List<Store> _stores = [];
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
    final frequency = await service.getFrequency();
    final dayOfMonth = await service.getDayOfMonth();
    final stores = await DatabaseService.instance.getStores();
    final username = await UserService.instance.username ?? '';
    final isAdmin = await UserService.instance.isAdmin;
    if (!mounted) return;
    setState(() {
      _weekday = weekday;
      _hour = hour;
      _leadDays = leadDays;
      _frequency = frequency;
      _dayOfMonth = dayOfMonth;
      _stores = stores;
      _username = username;
      _isAdmin = isAdmin;
      _loading = false;
    });
  }

  Future<void> _signOut() async {
    await UserService.instance.signOut();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    await _load();
  }

  Future<void> _cleanupDuplicates() => _run(() async {
        final removed = await DatabaseService.instance.mergeDuplicates();
        await NotificationService.instance.rescheduleAll();
        _snack(removed == 0
            ? 'No duplicate rows found.'
            : 'Merged $removed duplicate row(s) — quantities were combined.');
      });

  Future<void> _renameStore(Store store) async {
    final controller = TextEditingController(text: store.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename store branch'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Store name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == store.name) return;
    await DatabaseService.instance.renameStore(store.id, newName);
    // Store names appear in scheduled reminder text.
    await NotificationService.instance.rescheduleAll();
    await _load();
    _snack('Renamed to "$newName".');
  }

  Future<void> _saveNotificationSettings() async {
    await NotificationService.instance.saveSettings(
      weekday: _weekday,
      hour: _hour,
      leadDays: _leadDays,
      frequency: _frequency,
      dayOfMonth: _dayOfMonth,
    );
    _snack('Notification schedule updated.');
  }

  Future<void> _exportExcel(Store store) => _run(() async {
        final products =
            await DatabaseService.instance.getAll(storeId: store.id);
        if (products.isEmpty) {
          _snack('No products in ${store.name} to export yet.');
          return;
        }
        if (!mounted) return;
        final options = await showReportOptionsDialog(context);
        if (options == null) return;
        final filtered = options.apply(products);
        if (filtered.isEmpty) {
          _snack('No products match the selected dates.');
          return;
        }
        final deletionLog =
            await DatabaseService.instance.getDeletionLog(storeId: store.id);
        await ExportService.instance.shareExcelReport(filtered,
            storeName: store.name,
            options: options,
            deletionLog: deletionLog,
            generatedBy: _username);
      });

  Future<void> _exportAllStores() => _run(() async {
        final products = await DatabaseService.instance.getAll();
        if (products.isEmpty) {
          _snack('No products to export yet.');
          return;
        }
        if (!mounted) return;
        final options = await showReportOptionsDialog(context);
        if (options == null) return;
        final filtered = options.apply(products);
        if (filtered.isEmpty) {
          _snack('No products match the selected dates.');
          return;
        }
        final deletionLog = await DatabaseService.instance.getDeletionLog();
        await ExportService.instance.shareExcelReport(
          filtered,
          storeName: 'All Stores',
          options: options,
          storeNames: {for (final s in _stores) s.id: s.name},
          deletionLog: deletionLog,
          generatedBy: _username,
        );
      });

  Future<void> _backup() => _run(() async {
        final products = await DatabaseService.instance.getAll();
        if (products.isEmpty) {
          _snack('No products to back up yet.');
          return;
        }
        await ExportService.instance.shareJsonBackup(products, _stores);
      });

  Future<void> _restore() => _run(() async {
        final picked = await FilePicker.pickFiles(
          type: FileType.any,
          withData: false,
        );
        final path = picked?.files.single.path;
        if (path == null) return;
        final content = await File(path).readAsString();
        final backup = ExportService.instance.parseBackup(content);

        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Restore backup?'),
            content: Text(
                'This will replace your current inventory with '
                '${backup.products.length} product(s) from the backup file.'),
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

        await DatabaseService.instance
            .replaceAll(backup.products, stores: backup.stores);
        await NotificationService.instance.rescheduleAll();
        await _load();
        _snack('Restored ${backup.products.length} product(s).');
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
                _sectionTitle('Profile'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(_username.isNotEmpty
                              ? _username[0].toUpperCase()
                              : '?'),
                        ),
                        title: Text(
                          _username.isNotEmpty ? _username : 'Not signed in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle:
                            Text(_isAdmin ? 'Administrator' : 'Staff'),
                        trailing: IconButton(
                          tooltip:
                              _username.isNotEmpty ? 'Switch user' : 'Sign in',
                          icon: const Icon(Icons.logout),
                          onPressed: _busy ? null : _signOut,
                        ),
                      ),
                      if (_isAdmin) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.group),
                          title: const Text('Manage users'),
                          subtitle: const Text(
                              'Create up to 10 staff accounts — only the '
                              'admin can see them'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const UsersScreen()),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('Store branches'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < _stores.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.store),
                          title: Text(_stores[i].name),
                          subtitle: const Text('Tap to rename'),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: _busy ? null : () => _renameStore(_stores[i]),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('Stock dashboard notifications'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.repeat),
                        title: const Text('Frequency'),
                        trailing: DropdownButton<String>(
                          value: _frequency,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(
                                value: 'weekly', child: Text('Weekly')),
                            DropdownMenuItem(
                                value: 'monthly', child: Text('Monthly')),
                          ],
                          onChanged: (v) =>
                              setState(() => _frequency = v ?? _frequency),
                        ),
                      ),
                      if (_frequency == 'weekly')
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
                        )
                      else
                        ListTile(
                          leading: const Icon(Icons.calendar_month),
                          title: const Text('Day of month'),
                          trailing: DropdownButton<int>(
                            value: _dayOfMonth,
                            underline: const SizedBox.shrink(),
                            items: List.generate(28, (i) => i + 1)
                                .map((d) => DropdownMenuItem(
                                    value: d, child: Text('$d')))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _dayOfMonth = v ?? _dayOfMonth),
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
                          items: NotificationService.leadDayOptions
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
                _sectionTitle('Excel reports'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.storefront),
                        title: const Text('Export All Stores (combined)'),
                        subtitle: const Text(
                            'Every branch in one report with a Store column'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : _exportAllStores,
                      ),
                      for (final store in _stores) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.table_view),
                          title: Text('Export ${store.name}'),
                          subtitle: const Text(
                              'Inventory with brand, batch, expiry and status'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _busy ? null : () => _exportExcel(store),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('Inventory maintenance'),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.merge_type),
                    title: const Text('Clean up duplicate rows'),
                    subtitle: const Text(
                        'Merges rows with the same brand, product, batch, '
                        'category and expiry (ignoring case and spacing) by '
                        'combining quantities'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : _cleanupDuplicates,
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('Cloud sync'),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.sync),
                    title: const Text('Supabase live sync'),
                    subtitle: Text(SyncService.instance.isSignedIn
                        ? 'On — ${SyncService.instance.syncEmail}'
                        : 'Multi-device sync for products & store names'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const CloudSyncScreen()),
                      );
                      if (mounted) setState(() {});
                    },
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
                        title: Text('Local-first, optional cloud sync'),
                        subtitle: Text(
                            'Products are stored on-device (SQLite) with offline AI scanning. Optional Supabase sync keeps multiple phones up to date.'),
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
