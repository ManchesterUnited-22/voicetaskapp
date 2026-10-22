import '../../../core/config.dart';
import '../../../core/format.dart';
import '../../../core/vi_text.dart';
import '../../tasks/domain/app_task.dart';
import '../../tasks/domain/auto_scheduler.dart';
import '../../tasks/domain/reminder_scheduler.dart';
import '../../tasks/domain/task_repository.dart';
import 'ai_command.dart';

/// Hành động đang chờ người dùng xác nhận (vd xóa hàng loạt).
class _PendingConfirm {
  final DateTime at;
  final Future<String> Function() run;
  _PendingConfirm(this.at, this.run);
}

/// Thao tác gần nhất, dùng cho "hoàn tác".
class _Undo {
  final DateTime at;
  final String label;
  final Future<void> Function() revert;
  _Undo(this.at, this.label, this.revert);
}

/// Điều phối luồng ở Hình 2/3: văn bản → Gemini → (Auto-Scheduling) → Firestore
/// → Push Notification → câu phản hồi (TTS). Giữ trạng thái Pending Clarification (mục 4.5),
/// xác nhận xóa hàng loạt và hoàn tác thao tác gần nhất.
class CommandHandler {
  final CommandParser parser;
  final TaskRepository repo;
  final ReminderScheduler reminders;
  final AutoScheduler scheduler;
  final Future<String> Function(String period) performanceReply;
  final DateTime Function() clock;

  CommandHandler({
    required this.parser,
    required this.repo,
    required this.reminders,
    required this.performanceReply,
    this.scheduler = const AutoScheduler(),
    this.clock = DateTime.now,
  });

  static const _pendingTtl = Duration(minutes: 2);
  static const _undoTtl = Duration(minutes: 10);
  static const _confirmDeleteFrom = 2; // xóa từ 2 việc trở lên thì hỏi xác nhận

  static const _yes = <String>{
    'có', 'ok', 'oke', 'đồng ý', 'xác nhận', 'chắc chắn', 'được', 'ừ',
    'vâng', 'dạ', 'đúng rồi', 'làm đi', 'xóa đi', 'xoá đi',
  };
  static const _cancel = <String>{
    'thôi', 'bỏ qua', 'hủy', 'huỷ', 'không cần', 'thôi khỏi', 'dừng lại',
    'thôi bỏ đi',
  };

  String? _pendingValue; // lệnh trước đang chờ làm rõ (tự hết hạn sau 2 phút)
  DateTime? _pendingAt;
  _PendingConfirm? _confirm;
  _Undo? _undo;

  String? get _pending {
    final at = _pendingAt;
    if (_pendingValue != null &&
        at != null &&
        clock().difference(at) > _pendingTtl) {
      _pendingValue = null;
      _pendingAt = null;
    }
    return _pendingValue;
  }

  set _pending(String? v) {
    _pendingValue = v;
    _pendingAt = v == null ? null : clock();
  }

  bool get awaitingClarification => _pending != null;

  bool get awaitingConfirmation {
    final c = _confirm;
    if (c != null && clock().difference(c.at) > _pendingTtl) _confirm = null;
    return _confirm != null;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _isUndo(String n) =>
      n.contains('hoàn tác') ||
      n.contains('khôi phục') ||
      n.contains('phục hồi') ||
      n == 'undo';

  Future<String> handle(String text) async {
    final raw = text.trim();
    if (raw.isEmpty) return 'Mình chưa nghe rõ, bạn nói lại nhé.';
    final now = clock();
    final n = _norm(raw);

    // 1) Đang chờ xác nhận (xóa hàng loạt).
    final conf = _confirm;
    if (conf != null) {
      _confirm = null;
      if (now.difference(conf.at) <= _pendingTtl) {
        if (_yes.contains(n)) return conf.run();
        if (n == 'không' || _cancel.contains(n)) {
          return 'Mình đã hủy, chưa xóa gì cả.';
        }
        // Câu khác → bỏ xác nhận, xử lý như lệnh mới.
      }
    }
    // 2) Hoàn tác thao tác gần nhất.
    if (_isUndo(n)) return _undoLast(now);
    // 3) Bỏ dở câu hỏi làm rõ.
    if (_pending != null && _cancel.contains(n)) {
      _pending = null;
      return 'Mình đã bỏ qua yêu cầu trước nhé.';
    }

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
      return vietnameseOr(cmd.question, 'Bạn có thể nói rõ hơn được không?');
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
      case Intent.chitchat:
        return _chitchat(cmd);
      default:
        return 'Mình chưa hiểu yêu cầu này. Bạn thử nói như "sáng mai 9h họp dự án" nhé.';
    }
  }

  String _chitchat(AiCommand c) {
    // Nếu mô hình lỡ trả lời tiếng Anh thì dùng câu tiếng Việt mặc định.
    return vietnameseOr(c.reply,
        'Chào bạn! Mình là trợ lý công việc, bạn cần mình xếp lịch gì không?');
  }

  Future<String> _undoLast(DateTime now) async {
    final u = _undo;
    _undo = null;
    if (u == null || now.difference(u.at) > _undoTtl) {
      return 'Mình không còn thao tác nào để hoàn tác.';
    }
    await u.revert();
    return 'Đã hoàn tác: ${u.label}.';
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
    _undo = _Undo(now, 'tạo "$title"', () async {
      await reminders.cancelForTask(saved);
      await repo.delete(saved.id);
    });

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
    if (t.length > 1 && c.isBatch) return _updateMany(c, t, tasks, now);
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
    final updated = next;
    _undo = _Undo(now, 'sửa "${old.title}"', () async {
      await repo.update(old);
      await reminders.cancelForTask(updated);
      await reminders.scheduleForTask(old);
    });
    return moved
        ? 'Đã dời "${next.title}" sang ${formatDateTimeVi(next.dueDate, now)}.'
        : 'Đã cập nhật "${next.title}".';
  }

  /// Dời / đổi ưu tiên hàng loạt: các việc được xếp lần lượt, không chồng nhau.
  Future<String> _updateMany(
      AiCommand c, List<AppTask> targets, List<AppTask> all, DateTime now) async {
    if (c.dueDate == null && c.priority == null && c.durationMinutes == null) {
      _pending = 'Sửa hàng loạt ${targets.length} việc nhưng chưa nói đổi gì';
      return 'Bạn muốn dời ${targets.length} việc này sang lúc nào?';
    }
    if (c.dueDate != null &&
        c.dueDate!.isBefore(now.subtract(const Duration(minutes: 1)))) {
      _pending = 'Dời ${targets.length} việc nhưng thời điểm nói đã ở quá khứ';
      return 'Thời điểm đó đã qua rồi. Bạn muốn dời ${targets.length} việc sang lúc nào?';
    }
    final ids = targets.map((e) => e.id).toSet();
    // Lịch cố định = mọi việc không bị dời; việc vừa dời được thêm dần vào.
    final busy = all.where((x) => !ids.contains(x.id)).toList();
    final ordered = [...targets]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final moved = <(AppTask, AppTask)>[]; // (bản cũ, bản mới)
    for (final old in ordered) {
      var next = old;
      if (c.dueDate != null) {
        final slot = scheduler.findSlot(
          requested: c.dueDate,
          durationMinutes: c.durationMinutes ?? old.durationMinutes,
          existing: busy,
          now: now,
        );
        next = next.copyWith(
          dueDate: slot.start,
          rescheduleCount: old.rescheduleCount + 1,
        );
      }
      if (c.priority != null) next = next.copyWith(priority: c.priority);
      if (c.durationMinutes != null) {
        next = next.copyWith(durationMinutes: c.durationMinutes);
      }
      await repo.update(next);
      await reminders.cancelForTask(old);
      await reminders.scheduleForTask(next);
      busy.add(next);
      moved.add((old, next));
    }
    _undo = _Undo(now, 'sửa ${targets.length} việc', () async {
      for (final (old, next) in moved) {
        await repo.update(old);
        await reminders.cancelForTask(next);
        await reminders.scheduleForTask(old);
      }
    });
    return c.dueDate != null
        ? 'Đã dời ${targets.length} việc, xếp lần lượt từ ${formatDateTimeVi(c.dueDate!, now)}.'
        : 'Đã cập nhật ${targets.length} việc.';
  }

  Future<String> _delete(AiCommand c, List<AppTask> tasks) async {
    final t = _targets(c, tasks);
    if (t.isEmpty) return 'Không có công việc nào khớp để xóa.';
    if (t.length >= _confirmDeleteFrom) {
      _confirm = _PendingConfirm(clock(), () => _deleteNow(t));
      final names = t.take(3).map((e) => e.title).join(', ');
      final more = t.length > 3 ? ' và ${t.length - 3} việc khác' : '';
      return 'Mình sắp xóa ${t.length} việc: $names$more. Bạn xác nhận nhé?';
    }
    return _deleteNow(t);
  }

  Future<String> _deleteNow(List<AppTask> t) async {
    for (final x in t) {
      await reminders.cancelForTask(x);
      await repo.delete(x.id);
    }
    _undo = _Undo(
      clock(),
      t.length == 1 ? 'xóa "${t.first.title}"' : 'xóa ${t.length} việc',
      () async {
        for (final x in t) {
          final saved = await repo.add(x);
          try {
            await reminders.scheduleForTask(saved);
          } catch (_) {} // việc quá hạn có thể không đặt nhắc được
        }
      },
    );
    return t.length == 1
        ? 'Đã xóa "${t.first.title}".'
        : 'Đã xóa ${t.length} công việc.';
  }

  Future<String> _complete(AiCommand c, List<AppTask> tasks, DateTime now) async {
    final t = _targets(c, tasks).where((x) => !x.isCompleted).toList();
    if (t.isEmpty) return 'Không có công việc nào cần đánh dấu hoàn thành.';
    final created = <AppTask>[];
    for (final x in t) {
      await reminders.cancelForTask(x);
      await repo.update(x.copyWith(isCompleted: true, completedAt: now));
      final next = x.nextOccurrence('', newNotificationId());
      if (next != null) {
        final saved = await repo.add(next);
        await reminders.scheduleForTask(saved);
        created.add(saved);
      }
    }
    _undo = _Undo(now, 'hoàn thành ${t.length} việc', () async {
      for (final s in created) {
        await reminders.cancelForTask(s);
        await repo.delete(s.id);
      }
      for (final x in t) {
        await repo.update(x); // x là bản chưa hoàn thành
        try {
          await reminders.scheduleForTask(x);
        } catch (_) {}
      }
    });
    return t.length == 1
        ? 'Đã hoàn thành "${t.first.title}". Làm tốt lắm!'
        : 'Đã đánh dấu hoàn thành ${t.length} công việc.';
  }

  /// Trả lời "hôm nay / ngày mai / từ 2h đến 5h chiều... có việc gì".
  /// Có việc trong khoảng đó thì liệt kê, không có thì nói rõ là không có.
  String _query(AiCommand c, List<AppTask> tasks, DateTime now) {
    final filter = c.queryFilter ?? 'all';
    final hasRange = c.rangeStart != null || c.rangeEnd != null;
    final today = DateTime(now.year, now.month, now.day);
    var from = c.rangeStart ?? today;
    var to = c.rangeEnd ?? from.add(const Duration(days: 1));
    if (!to.isAfter(from)) {
      // Mô hình đưa khoảng rỗng/ngược: lấy trọn ngày của mốc được nói.
      if (c.rangeStart == null && c.rangeEnd != null) {
        from = DateTime(to.year, to.month, to.day);
      }
      to = DateTime(from.year, from.month, from.day).add(const Duration(days: 1));
      from = DateTime(from.year, from.month, from.day);
    }
    final label = formatRangeVi(from, to, now); // vd "hôm nay", "ngày mai"
    final singleDay = isSameDay(from, to.subtract(const Duration(minutes: 1)));

    String when(AppTask t) => singleDay || isSameDay(t.dueDate, now)
        ? formatTimeVi(t.dueDate)
        : formatDateTimeVi(t.dueDate, now);
    String describe(List<AppTask> l, {bool withTime = true}) {
      final shown = l
          .take(6)
          .map((t) => withTime ? '${when(t)} ${t.title}' : t.title)
          .join(', ');
      final more = l.length > 6 ? ' và ${l.length - 6} việc khác' : '';
      return '$shown$more';
    }

    bool inWindow(DateTime d) => !d.isBefore(from) && d.isBefore(to);

    // Việc đã hoàn thành: lọc theo thời điểm hoàn thành.
    List<AppTask> doneIn() {
      DateTime at(AppTask t) => t.completedAt ?? t.dueDate;
      return tasks.where((t) => t.isCompleted && inWindow(at(t))).toList()
        ..sort((a, b) => at(a).compareTo(at(b)));
    }

    if (filter == 'done') {
      final done = doneIn();
      if (done.isEmpty) return 'Bạn chưa hoàn thành việc nào $label.';
      return 'Bạn đã hoàn thành ${done.length} việc $label: ${describe(done, withTime: false)}.';
    }

    // Hỏi "quá hạn" mà không nêu khoảng thời gian → xét mọi việc quá hạn.
    final noRange = filter == 'overdue' && !hasRange;
    final inRange = tasks
        .where((t) => !t.isCompleted && (noRange || inWindow(t.dueDate)))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final overdue = inRange.where((t) => t.isOverdue(now)).toList();
    final upcoming = inRange.where((t) => !t.isOverdue(now)).toList();
    final where = noRange ? '' : ' $label';

    if (filter == 'overdue') {
      if (overdue.isEmpty) return 'Bạn không có việc nào quá hạn$where.';
      return 'Bạn có ${overdue.length} việc quá hạn$where: ${describe(overdue)}.';
    }
    if (filter == 'upcoming') {
      if (upcoming.isEmpty) return 'Bạn không có việc nào sắp tới hạn $label.';
      return 'Bạn có ${upcoming.length} việc sắp tới hạn $label: ${describe(upcoming)}.';
    }

    // filter == 'all'
    if (inRange.isEmpty) {
      final done = doneIn();
      if (done.isEmpty) return 'Bạn không có công việc nào $label.';
      // Có việc nhưng đều đã xong: nói rõ để không gây hiểu nhầm.
      return 'Bạn không còn việc nào cần làm $label. '
          'Bạn đã hoàn thành ${done.length} việc: ${describe(done, withTime: false)}.';
    }
    final sb = StringBuffer(
        'Bạn có ${inRange.length} việc $label: ${describe(inRange)}.');
    if (overdue.isNotEmpty && upcoming.isNotEmpty) {
      sb.write(' Trong đó ${overdue.length} việc đã quá hạn.');
    } else if (overdue.isNotEmpty) {
      sb.write(' Tất cả đều đã quá hạn.');
    }
    return sb.toString();
  }
}