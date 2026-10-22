import 'dart:math';

import 'app_task.dart';

/// Id chẵn n: nhắc trước hạn; n+1: cảnh báo quá hạn.
int newNotificationId() => Random().nextInt(0x3FFFFFFF) * 2;

/// Cổng trừu tượng tới Push Notification Scheduler.
abstract class ReminderScheduler {
  Future<void> scheduleForTask(AppTask task);
  Future<void> cancelForTask(AppTask task);
}
