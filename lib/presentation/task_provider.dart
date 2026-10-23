import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/activity/domain/activity_entry.dart';
import '../features/activity/domain/activity_log.dart';
import '../features/tasks/domain/app_task.dart';
import '../features/tasks/domain/reminder_scheduler.dart';
import '../features/tasks/domain/task_repository.dart';

class TaskProvider extends ChangeNotifier {
  final TaskRepository repo;
  final ReminderScheduler reminders;

  /// Nhật ký hoạt động dùng chung (thao tác tay trên giao diện được ghi với source = 'ui').
  final ActivityLog? log;
  StreamSubscription<List<AppTask>>? _sub;
  List<AppTask> _tasks = const [];
  Object? error;
  bool _synced = false;

  TaskProvider(this.repo, this.reminders, {this.log}) {
    _sub = repo.watchTasks().listen((t) {
      _tasks = t;
      if (!_synced) {
        _synced = true;
        // Đăng ký lại thông báo cho mọi việc chưa xong (đổi máy, cài lại app, đổi múi giờ).
        for (final x in t.where((x) => !x.isCompleted)) {
          reminders.scheduleForTask(x);
        }
      }
      error = null;
      notifyListeners();
    }, onError: (Object e) {
      error = e;
      notifyListeners();
    });
  }

  List<AppTask> get all => _tasks;

  List<AppTask> get overdue {
    final now = DateTime.now();
    return _tasks.where((t) => t.isOverdue(now)).toList();
  }

  List<AppTask> get upcoming {
    final now = DateTime.now();
    return _tasks.where((t) => !t.isCompleted && !t.dueDate.isBefore(now)).toList();
  }

  List<AppTask> get completed => _tasks.where((t) => t.isCompleted).toList()
    ..sort((a, b) => b.dueDate.compareTo(a.dueDate));

  Future<void> toggle(AppTask t) async {
    if (!t.isCompleted) {
      await repo.update(t.copyWith(isCompleted: true, completedAt: DateTime.now()));
      await reminders.cancelForTask(t);
      final next = t.nextOccurrence('', newNotificationId());
      AppTask? savedNext;
      if (next != null) {
        savedNext = await repo.add(next);
        await reminders.scheduleForTask(savedNext);
      }
      log?.record(
        'complete',
        source: 'ui',
        items: [ActivityItem(t.id, t.title)],
        summary: savedNext == null
            ? null
            : 'Tự tạo lần lặp kế tiếp: ${savedNext.dueDate.toIso8601String().substring(0, 16)}',
      );
      return;
    }
    // copyWith không xóa được completedAt → dựng lại bản chưa hoàn thành.
    final reopened = AppTask(
      id: t.id,
      title: t.title,
      dueDate: t.dueDate,
      priority: t.priority,
      notificationId: t.notificationId,
      createdAt: t.createdAt,
      isRecurring: t.isRecurring,
      recurrenceRule: t.recurrenceRule,
      durationMinutes: t.durationMinutes,
      rescheduleCount: t.rescheduleCount,
    );
    await repo.update(reopened);
    await reminders.scheduleForTask(reopened);
    log?.record('reopen', source: 'ui', items: [ActivityItem(t.id, t.title)]);
  }

  /// Thêm mới (id rỗng) hoặc cập nhật task từ form nhập tay.
  Future<void> save(AppTask t) async {
    final old = t.id.isEmpty ? null : _tasks.where((x) => x.id == t.id).firstOrNull;
    final toSave = (old != null && old.dueDate != t.dueDate)
        ? t.copyWith(rescheduleCount: old.rescheduleCount + 1)
        : t;
    final saved = t.id.isEmpty ? await repo.add(toSave) : toSave;
    if (t.id.isNotEmpty) await repo.update(toSave);
    await reminders.scheduleForTask(saved);
    if (t.id.isEmpty) {
      log?.record('create',
          source: 'ui',
          items: [ActivityItem(saved.id, saved.title, to: saved.dueDate)]);
    } else {
      final moved = old != null && old.dueDate != t.dueDate;
      log?.record(moved ? 'move' : 'edit', source: 'ui', items: [
        ActivityItem(t.id, t.title,
            from: moved ? old!.dueDate : null, to: moved ? t.dueDate : null),
      ]);
    }
  }

  Future<void> remove(AppTask t) async {
    await reminders.cancelForTask(t);
    await repo.delete(t.id);
    log?.record('delete',
        source: 'ui', items: [ActivityItem(t.id, t.title, from: t.dueDate)]);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}