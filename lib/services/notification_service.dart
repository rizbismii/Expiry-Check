import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/product.dart';
import '../models/store.dart';
import 'database_service.dart';

/// Schedules on-device notifications (no push server needed):
/// - a weekly digest of items expiring within the alert window
/// - a per-product reminder a few days before it expires and on expiry day
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _weeklyDigestId = 1;
  static const _weekdayKey = 'weekly_digest_weekday';
  static const _hourKey = 'weekly_digest_hour';
  static const _leadDaysKey = 'reminder_lead_days';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name.identifier));
    } catch (_) {
      // Fall back to UTC if the device timezone can't be resolved.
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings:
          const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      await android.requestExactAlarmsPermission();
      return granted ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted =
          await ios.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return false;
  }

  // ---- Settings ----

  Future<int> getWeeklyWeekday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_weekdayKey) ?? DateTime.monday;
  }

  Future<int> getWeeklyHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_hourKey) ?? 9;
  }

  Future<int> getLeadDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_leadDaysKey) ?? 7;
  }

  Future<void> saveSettings({
    required int weekday,
    required int hour,
    required int leadDays,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_weekdayKey, weekday);
    await prefs.setInt(_hourKey, hour);
    await prefs.setInt(_leadDaysKey, leadDays);
    await rescheduleAll();
  }

  // ---- Scheduling ----

  static NotificationDetails _digestDetails(String body) => NotificationDetails(
        android: AndroidNotificationDetails(
          'weekly_digest',
          'Weekly expiry dashboard',
          channelDescription: 'Weekly stock dashboard with expiry summary',
          importance: Importance.high,
          priority: Priority.high,
          // Expands the notification so the whole dashboard is readable.
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(),
      );

  static const _productDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'expiry_alerts',
      'Expiry alerts',
      channelDescription: 'Reminders for individual products nearing expiry',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Rebuilds the entire schedule from the current product list and settings.
  Future<void> rescheduleAll() async {
    await init();
    await _plugin.cancelAll();

    final products = await DatabaseService.instance.getAll();
    final stores = await DatabaseService.instance.getStores();
    final storeNames = {for (final s in stores) s.id: s.name};
    final leadDays = await getLeadDays();

    await _scheduleWeeklyDigest(products, stores);
    for (final product in products) {
      await _scheduleProductReminders(
          product, leadDays, storeNames[product.storeId]);
    }
  }

  Future<void> _scheduleWeeklyDigest(
      List<Product> products, List<Store> stores) async {
    final weekday = await getWeeklyWeekday();
    final hour = await getWeeklyHour();

    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    while (next.weekday != weekday || !next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }

    final body = buildDashboardBody(products, stores);
    await _zonedSchedule(
      id: _weeklyDigestId,
      title: 'Weekly stock dashboard',
      body: body,
      when: next,
      details: _digestDetails(body),
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  /// Quantity-based dashboard shown in the weekly notification: total units
  /// and units per expiry band, overall and per store branch.
  static String buildDashboardBody(List<Product> products, List<Store> stores) {
    if (products.isEmpty) {
      return 'No products tracked yet. Scan your stock to start receiving '
          'expiry summaries.';
    }
    int units(Iterable<Product> ps) => ps.fold(0, (sum, p) => sum + p.quantity);

    String bandLine(List<Product> ps) {
      final expired = units(ps.where((p) => p.isExpired));
      final soon30 = units(ps.where((p) => p.isExpiringSoon));
      final soon90 = units(ps.where((p) => p.isExpiring90));
      final fresh = units(ps) - expired - soon30 - soon90;
      return 'Expired $expired • ≤30d $soon30 • ≤90d $soon90 • Fresh $fresh';
    }

    final lines = <String>[
      'Total stock: ${units(products)} units (${products.length} products)',
      bandLine(products),
    ];
    // Per-branch breakdown when more than one branch holds stock.
    final byStore = <int, List<Product>>{};
    for (final p in products) {
      byStore.putIfAbsent(p.storeId, () => []).add(p);
    }
    if (byStore.length > 1) {
      for (final store in stores) {
        final ps = byStore[store.id];
        if (ps == null || ps.isEmpty) continue;
        lines.add('${store.name}: ${units(ps)} units — ${bandLine(ps)}');
      }
    }
    return lines.join('\n');
  }

  Future<void> _scheduleProductReminders(
      Product product, int leadDays, String? storeName) async {
    if (product.id == null) return;
    final hour = await getWeeklyHour();
    final expiry = tz.TZDateTime(
      tz.local,
      product.expiryDate.year,
      product.expiryDate.month,
      product.expiryDate.day,
      hour,
    );
    final now = tz.TZDateTime.now(tz.local);

    final lead = expiry.subtract(Duration(days: leadDays));
    if (lead.isAfter(now)) {
      await _zonedSchedule(
        id: product.id! * 10 + 2,
        title: '${product.name} expires in $leadDays days',
        body: _productBody(product, storeName),
        when: lead,
        details: _productDetails,
      );
    }
    if (expiry.isAfter(now)) {
      await _zonedSchedule(
        id: product.id! * 10 + 3,
        title: '${product.name} expires today',
        body: _productBody(product, storeName),
        when: expiry,
        details: _productDetails,
      );
    }
  }

  String _productBody(Product product, String? storeName) {
    final parts = <String>[
      if (storeName != null && storeName.isNotEmpty) storeName,
      if (product.brand.isNotEmpty) 'Brand: ${product.brand}',
      if (product.batch.isNotEmpty) 'Batch: ${product.batch}',
      'Qty: ${product.quantity}',
    ];
    return parts.join(' • ');
  }

  Future<void> _zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required NotificationDetails details,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } catch (_) {
      // Scheduling can fail on devices with restricted alarm permissions;
      // the weekly digest still covers these products.
    }
  }
}
