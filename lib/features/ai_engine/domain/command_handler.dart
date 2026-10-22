import '../../../core/config.dart';
import '../../../core/format.dart';
import '../../tasks/domain/app_task.dart';
import '../../tasks/domain/auto_scheduler.dart';
import '../../tasks/domain/reminder_scheduler.dart';
import '../../tasks/domain/task_repository.dart';
import 'ai_command.dart';

/// Điều phối luồng ở Hình 2/3: văn bản → Gemini → (Auto-Scheduling) → Firestore
/// → Push Notification → câu phản hồi (TTS). Giữ trạng thái Pending Clarification (mục 4.5).
class CommandHandler {
  final CommandParser parser;
  final TaskRepository repo;
  final ReminderScheduler reminders;
  final AutoScheduler scheduler;
  final Future<String> Function(String period) performanceReply;
  final DateTime Function() clock;

  String? _pending; // lệnh trước đang chờ làm rõ

  CommandHandler({
    required this.parser,
    required this.repo,
    required this.reminders,
    required this.performanceReply,
    this.scheduler = const AutoScheduler(),
    this.clock = DateTime.now,
  });

  bool get awaitingClarification => _pending != null;

  Future<String> handle(String text) async {
    final raw = text.trim();
    if (raw.isEmpty) return 'Mình chưa nghe rõ, bạn nói lại nhé.';
    final now = clock();
    final tasks = await repo.getAll();

    final cmd = await parser.parse(
      text: raw,
      tasks: tasks,
      now: now,
      pendingContext: _pending,
    );
    await repo.logVoice(rawText: raw, intent: cmd.intent.name);

    if (cmd.intent == Intent.needClarification) {
      _pending = _pending == null ? raw : '$_pending | $raw';
      return cmd.question ?? 'Bạn có thể nói rõ hơn được không?';
    }
    _pending = null;

    switch (cmd.intent) {
      case Intent.createTask:
        return _create(cmd, tasks, now);
      case Intent.updateTask:
        return _update(cmd, tasks, now);
      case Intent.deleteTask:
        return _delete(cmd, tasks);
      case Intent.completeTask:
        return _complete(cmd, tasks, now);
      case Intent.queryTasks:
        return _query(cmd, tasks, now);
      case Intent.askPerformance:
        return performanceReply(cmd.period ?? 'week');
      default:
        return 'Mình chưa hiểu yêu cầu này. Bạn thử nói như "sáng mai 9h họp dự án" nhé.';
    }
  }

  Future<String> _create(AiCommand c, List<AppTask> tasks, DateTime now) async {
    final title = c.title;
    if (title == null || title.isEmpty) {
      _pending = 'Tạo việc mới nhưng chưa có tên';
      return 'Bạn muốn tạo công việc gì?';
    }
    if (c.dueDate != null &&
        c.dueDate!.isBefore(now.subtract(const Duration(minutes: 1)))) {
      _pending = 'Tạo "$title" nhưng thời điểm nói đã ở quá khứ';
      return 'Thời điểm đó đã qua rồi. Bạn muốn xếp "$title" vào lúc nào?';
    }
    final dur = c.durationMinutes ?? AppConfig.defaultDurationMinutes;
    final slot = scheduler.findSlot(
      requested: c.dueDate,
      durationMinutes: dur,
      existing: tasks,
      now: now,
    );
    final saved = await repo.add(AppTask(
      id: '',
      title: title,
      dueDate: slot.start,
      priority: c.priority ?? Priority.medium,
      notificationId: newNotificationId(),
      createdAt: now,
      durationMinutes: dur,
      isRecurring: c.recurrenceRule != null,
      recurrenceRule: c.recurrenceRule,
    ));
    await reminders.scheduleForTask(saved);

    final when = formatDateTimeVi(slot.start, now);
    if (slot.adjusted && c.dueDate != null) {
      return 'Khung ${formatTimeVi(c.dueDate!)} đã có việc khác nên mình xếp "$title" '
          'vào lúc $when.';
    }
    return 'Đã xếp lịch $title lúc $when.';
  }

  List<AppTask> _targets(AiCommand c, List<AppTask> tasks) {
    final ids = c.targetTaskIds.toSet();
    return tasks.where((t) => ids.contains(t.id)).toList();
  }

  Future<String> _update(AiCommand c, List<AppTask> tasks, DateTime now) async {
    final t = _targets(c, tasks);
    if (t.isEmpty) return 'Mình không tìm thấy công việc bạn muốn sửa.';
    if (t.length > 1) {
      _pending = 'Sửa lịch nhưng khớp nhiều việc: ${t.map((e) => e.title).join(', ')}';
      return 'Có nhiều việc khớp: ${t.map((e) => e.title).join(', ')}. Bạn muốn sửa việc nào?';
    }
    final old = t.first;
    var next = old;
    var moved = false;
    if (c.dueDate != null) {
      final slot = scheduler.findSlot(
        requested: c.dueDate,
        durationMinutes: c.durationMinutes ?? old.durationMinutes,
        existing: tasks,
        now: now,
        ignoreTaskId: old.id,
      );
      next = next.copyWith(
        dueDate: slot.start,
        rescheduleCount: old.rescheduleCount + 1,
      );
      moved = true;
    }
    if (c.title != null && c.title!.isNotEmpty) next = next.copyWith(title: c.title);
    if (c.priority != null) next = next.copyWith(priority: c.priority);
    if (c.durationMinutes != null) {
      next = next.copyWith(durationMinutes: c.durationMinutes);
    }
    await repo.update(next);
    // Đồng bộ AI ↔ Push: hủy đăng ký cũ, tạo đăng ký mới theo mốc cập nhật.
    await reminders.cancelForTask(old);
    await reminders.scheduleForTask(next);
    return moved
        ? 'Đã dời "${next.title}" sang ${formatDateTimeVi(next.dueDate, now)}.'
        : 'Đã cập nhật "${next.title}".';
  }

  Future<String> _delete(AiCommand c, List<AppTask> tasks) async {
    final t = _targets(c, tasks);
    if (t.isEmpty) return 'Không có công việc nào khớp để xóa.';
    for (final x in t) {
      await reminders.cancelForTask(x);
      await repo.delete(x.id);
    }
    return t.length == 1
        ? 'Đã xóa "${t.first.title}".'
        : 'Đã xóa ${t.length} công việc.';
  }

  Future<String> _complete(AiCommand c, List<AppTask> tasks, DateTime now) async {
    final t = _targets(c, tasks).where((x) => !x.isCompleted).toList();
    if (t.isEmpty) return 'Không có công việc nào cần đánh dấu hoàn thành.';
    for (final x in t) {
      await reminders.cancelForTask(x);
      await repo.update(x.copyWith(isCompleted: true, completedAt: now));
      final next = x.nextOccurrence('', newNotificationId());
      if (next != null) {
        final saved = await repo.add(next);
        await reminders.scheduleForTask(saved);
      }
    }
    return t.length == 1
        ? 'Đã hoàn thành "${t.first.title}". Làm tốt lắm!'
        : 'Đã đánh dấu hoàn thành ${t.length} công việc.';
  }

  String _query(AiCommand c, List<AppTask> tasks, DateTime now) {
    final from = c.rangeStart ?? DateTime(now.year, now.month, now.day);
    final to = c.rangeEnd ?? from.add(const Duration(days: 1));
    final list = tasks
        .where((t) =>
            !t.isCompleted && !t.dueDate.isBefore(from) && t.dueDate.isBefore(to))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (list.isEmpty) return 'Bạn không có công việc nào trong khoảng này.';
    final shown = list
        .take(8)
        .map((t) => '${formatTimeVi(t.dueDate)} ${t.title}')
        .join('; ');
    final more = list.length > 8 ? ' và ${list.length - 8} việc khác' : '';
    return 'Bạn có ${list.length} việc: $shown$more.';
  }
}
