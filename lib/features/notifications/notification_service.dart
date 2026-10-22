import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/config.dart';
import '../tasks/domain/app_task.dart' show AppTask; // tránh trùng tên Priority với plugin
import '../tasks/domain/reminder_scheduler.dart';

/// Push Notification Scheduler (mục 4.4).
/// Mỗi task dùng notificationId = n (chẵn) cho nhắc trước hạn và n+1 cho cảnh báo quá hạn,
/// nên khi dời/hủy/hoàn thành chỉ cần hủy hai id này rồi đăng ký lại.
class NotificationService implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (kIsWeb) return;
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
    }
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(init);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'tasks_channel',
      'Nhắc việc',
      channelDescription: 'Nhắc việc sắp đến hạn và cảnh báo quá hạn',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> scheduleForTask(AppTask t) async {
    if (kIsWeb) return;
    await cancelForTask(t);
    if (t.isCompleted) return;
    final now = DateTime.now();

    final remindAt =
        t.dueDate.subtract(const Duration(minutes: AppConfig.reminderLeadMinutes));
    if (remindAt.isAfter(now)) {
      await _schedule(
        t.notificationId,
        '⏰ Sắp đến hạn',
        '${t.title} bắt đầu sau ${AppConfig.reminderLeadMinutes} phút',
        remindAt,
      );
    }
    final overdueAt =
        t.dueDate.add(const Duration(minutes: AppConfig.overdueDelayMinutes));
    if (overdueAt.isAfter(now)) {
      await _schedule(
        t.notificationId + 1,
        '⚠️ Công việc quá hạn',
        '${t.title} đã quá hạn. Hoàn thành hoặc dời lịch nhé!',
        overdueAt,
      );
    }
  }

  @override
  Future<void> cancelForTask(AppTask t) async {
    if (kIsWeb) return;
    await _plugin.cancel(t.notificationId);
    await _plugin.cancel(t.notificationId + 1);
  }

  /// Gửi ngay (dùng cho lời khuyên của AI Coach).
  Future<void> showNow(String title, String body) async {
    if (kIsWeb) return;
    await  _plugin.show(Random().nextInt(0x7FFFFFFF), title, body, _details);
  }

  Future<void> _schedule(int id, String title, String body, DateTime at) =>
      _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
}
