import 'package:flutter_test/flutter_test.dart';
import 'package:voice_task_app/features/ai_engine/domain/ai_command.dart';
import 'package:voice_task_app/features/ai_engine/domain/command_handler.dart';
import 'package:voice_task_app/features/tasks/domain/app_task.dart';
import 'package:voice_task_app/features/tasks/domain/reminder_scheduler.dart';
import 'package:voice_task_app/features/tasks/domain/task_repository.dart';

class FakeRepo implements TaskRepository {
  final Map<String, AppTask> store = {};
  final logs = <String>[];
  int _n = 0;

  @override
  Future<AppTask> add(AppTask t) async {
    final saved = AppTask(
      id: 'id${_n++}',
      title: t.title,
      dueDate: t.dueDate,
      priority: t.priority,
      notificationId: t.notificationId,
      createdAt: t.createdAt,
      durationMinutes: t.durationMinutes,
      isCompleted: t.isCompleted,
      isRecurring: t.isRecurring,
      recurrenceRule: t.recurrenceRule,
      completedAt: t.completedAt,
      rescheduleCount: t.rescheduleCount,
    );
    store[saved.id] = saved;
    return saved;
  }

  @override
  Future<void> delete(String id) async => store.remove(id);
  @override
  Future<List<AppTask>> getAll() async => store.values.toList();
  @override
  Future<List<AppTask>> getBetween(DateTime a, DateTime b) async => store.values
      .where((t) => !t.dueDate.isBefore(a) && t.dueDate.isBefore(b))
      .toList();
  @override
  Future<void> update(AppTask t) async => store[t.id] = t;
  @override
  Future<void> logVoice({required String rawText, required String intent}) async =>
      logs.add(intent);
  final activity = <Map<String, dynamic>>[];
  @override
  Future<void> saveActivity(Map<String, dynamic> data) async => activity.add(data);
  @override
  Future<void> markActivityUndone(String id) async {}
  @override
  Future<List<Map<String, dynamic>>> loadActivity({int limit = 30}) async => [];
  DateTime? lastCoach;
  @override
  Future<DateTime?> getLastDailyCoach() async => lastCoach;
  @override
  Future<void> setLastDailyCoach(DateTime d) async => lastCoach = d;
  @override
  Future<void> saveAnalytics(Map<String, dynamic> data) async {}
  @override
  Stream<List<AppTask>> watchTasks() => const Stream.empty();
}

class FakeReminders implements ReminderScheduler {
  final scheduled = <int>[];
  final cancelled = <int>[];
  @override
  Future<void> scheduleForTask(AppTask t) async => scheduled.add(t.notificationId);
  @override
  Future<void> cancelForTask(AppTask t) async => cancelled.add(t.notificationId);
}

class FakeParser implements CommandParser {
  final List<AiCommand> queue;
  final contexts = <String?>[];
  final altsSeen = <List<String>>[];
  FakeParser(this.queue);
  @override
  Future<AiCommand> parse({
    required String text,
    required List<AppTask> tasks,
    DateTime? now,
    String? pendingContext,
    String? recentActions,
    List<String> alternatives = const [],
  }) async {
    contexts.add(pendingContext);
    altsSeen.add(alternatives);
    return queue.removeAt(0);
  }
}

void main() {
  final now = DateTime(2026, 10, 21, 17, 46);
  late FakeRepo repo;
  late FakeReminders rem;

  CommandHandler build(List<AiCommand> cmds, [FakeParser? p]) {
    repo = FakeRepo();
    rem = FakeReminders();
    return CommandHandler(
      parser: p ?? FakeParser(cmds),
      repo: repo,
      reminders: rem,
      performanceReply: (p) async => 'perf:$p',
      clock: () => now,
    );
  }

  test('createTask: lưu task, đăng ký push, phản hồi giờ', () async {
    final h = build([
      AiCommand(
          intent: Intent.createTask,
          title: 'Họp dự án FPT',
          dueDate: DateTime(2026, 10, 22, 9)),
    ]);
    final reply = await h.handle('Sáng mai 9h họp dự án FPT');
    expect(reply, 'Đã xếp lịch Họp dự án FPT lúc 9h ngày mai.');
    expect(repo.store.length, 1);
    expect(repo.store.values.first.priority, Priority.medium);
    expect(rem.scheduled.length, 1);
    expect(repo.logs, ['createTask']);
  });

  test('createTask trùng giờ → dời sang 10h và báo lại', () async {
    final h = build([
      AiCommand(
          intent: Intent.createTask,
          title: 'A',
          dueDate: DateTime(2026, 10, 22, 9)),
      AiCommand(
          intent: Intent.createTask,
          title: 'B',
          dueDate: DateTime(2026, 10, 22, 9)),
    ]);
    await h.handle('A');
    final reply = await h.handle('B');
    expect(reply, contains('10h ngày mai'));
    final b = repo.store.values.firstWhere((t) => t.title == 'B');
    expect(b.dueDate, DateTime(2026, 10, 22, 10));
  });

  test('needClarification giữ trạng thái chờ rồi truyền ngữ cảnh', () async {
    final parser = FakeParser([
      const AiCommand(intent: Intent.needClarification, question: 'Dời sang mấy giờ?'),
      AiCommand(intent: Intent.updateTask, targetTaskIds: const ['id0'], dueDate: DateTime(2026, 10, 22, 15)),
    ]);
    final h = build([], parser);
    final t = await repo.add(AppTask(
      id: '',
      title: 'Họp',
      dueDate: DateTime(2026, 10, 22, 9),
      priority: Priority.medium,
      notificationId: 10,
      createdAt: now,
    ));
    expect(t.id, 'id0');

    expect(await h.handle('Sửa lịch họp'), 'Dời sang mấy giờ?');
    expect(h.awaitingClarification, true);

    final reply = await h.handle('3 giờ chiều');
    expect(h.awaitingClarification, false);
    expect(parser.contexts, [null, 'Sửa lịch họp']);
    expect(reply, contains('15h ngày mai'));
    expect(repo.store['id0']!.dueDate, DateTime(2026, 10, 22, 15));
    expect(repo.store['id0']!.rescheduleCount, 1);
    // hủy push cũ rồi đăng ký lại
    expect(rem.cancelled, [10]);
    expect(rem.scheduled, [10]);
  });

  test('giờ ở quá khứ → hỏi lại, không lưu', () async {
    final h = build([
      AiCommand(
          intent: Intent.createTask,
          title: 'A',
          dueDate: DateTime(2026, 10, 20, 9)),
    ]);
    final reply = await h.handle('A hôm qua 9h');
    expect(reply, contains('đã qua'));
    expect(repo.store, isEmpty);
    expect(h.awaitingClarification, true);
  });

  test('hoàn thành task lặp hàng ngày → tạo lần kế tiếp', () async {
    final h = build([
      const AiCommand(intent: Intent.completeTask, targetTaskIds: ['id0']),
    ]);
    await repo.add(AppTask(
      id: '',
      title: 'Uống thuốc',
      dueDate: DateTime(2026, 10, 21, 8),
      priority: Priority.low,
      notificationId: 6,
      createdAt: now,
      isRecurring: true,
      recurrenceRule: 'daily',
    ));
    await h.handle('xong uống thuốc');
    expect(repo.store.length, 2);
    final next = repo.store.values.firstWhere((t) => !t.isCompleted);
    expect(next.dueDate, DateTime(2026, 10, 22, 8));
  });

  Future<AppTask> addTask(String title, DateTime due, {int nid = 1}) =>
      repo.add(AppTask(
        id: '',
        title: title,
        dueDate: due,
        priority: Priority.low,
        notificationId: nid,
        createdAt: now,
      ));

  test('deleteTask hàng loạt: đọc lại danh sách, chờ xác nhận rồi mới xóa', () async {
    final h = build([
      const AiCommand(
          intent: Intent.deleteTask,
          targetTaskIds: ['id0', 'id1'],
          isBatch: true),
    ]);
    for (final n in ['x', 'y', 'z']) {
      await addTask(n, DateTime(2026, 10, 10));
    }
    final ask = await h.handle('xóa tất cả việc quá hạn');
    expect(ask, contains('xác nhận'));
    expect(repo.store.length, 3); // chưa xóa gì
    expect(await h.handle('có'), contains('Đã xóa 2 công việc'));
    expect(repo.store.keys, ['id2']);
  });

  test('xóa MỘT việc cũng đọc lại tên + giờ và chờ xác nhận', () async {
    final h = build([
      const AiCommand(intent: Intent.deleteTask, targetTaskIds: ['id0']),
    ]);
    await addTask('Họp dự án FPT', DateTime(2026, 10, 22, 9));
    final ask = await h.handle('xóa họp dự án');
    expect(ask, contains('Họp dự án FPT'));
    expect(ask, contains('xác nhận'));
    expect(repo.store.length, 1);
    expect(await h.handle('không'), contains('chưa xóa'));
    expect(repo.store.length, 1);
  });

  test('xóa: Gemini không chọn được việc → tìm gần đúng theo tên rồi hỏi lại', () async {
    final h = build([
      const AiCommand(intent: Intent.deleteTask), // targetTaskIds rỗng
    ]);
    await addTask('Họp dự án FPT', DateTime(2026, 10, 22, 9));
    await addTask('Đá bóng', DateTime(2026, 10, 22, 17), nid: 2);
    final ask = await h.handle('xóa hộp dự án'); // nghe sai "họp" → "hộp"
    expect(ask, contains('Họp dự án FPT'));
    expect(ask, isNot(contains('Đá bóng')));
    expect(repo.store.length, 2);
    expect(h.awaitingConfirmation, true);
    expect(await h.handle('đúng'), contains('Đã xóa'));
    expect(repo.store.values.map((t) => t.title), ['Đá bóng']);
  });

  test('xóa cụt (không có tên việc) → hỏi lại, không xóa gì', () async {
    final h = build([
      const AiCommand(intent: Intent.deleteTask),
    ]);
    await addTask('Họp dự án FPT', DateTime(2026, 10, 22, 9));
    final ask = await h.handle('xóa');
    expect(ask, contains('tên việc'));
    expect(repo.store.length, 1);
    expect(h.awaitingClarification, true);
  });

  test('xóa khớp nhiều việc (không nói "tất cả") → bắt chọn, không xóa hàng loạt', () async {
    final h = build([
      const AiCommand(
          intent: Intent.deleteTask, targetTaskIds: ['id0', 'id1']),
    ]);
    await addTask('Họp dự án', DateTime(2026, 10, 22, 9));
    await addTask('Họp phụ huynh', DateTime(2026, 10, 22, 15), nid: 2);
    final ask = await h.handle('xóa họp');
    expect(ask, contains('1.'));
    expect(ask, contains('2.'));
    expect(repo.store.length, 2);
    // chọn "cái thứ hai" → vẫn hỏi xác nhận xóa đúng việc đó
    final confirm = await h.handle('cái thứ hai');
    expect(confirm, contains('Họp phụ huynh'));
    expect(repo.store.length, 2);
    expect(await h.handle('có'), contains('Đã xóa "Họp phụ huynh"'));
    expect(repo.store.values.map((t) => t.title), ['Họp dự án']);
  });

  test('sửa/hoàn thành việc không khớp điều người dùng nói → hỏi "có phải...?"', () async {
    final h = build([
      const AiCommand(intent: Intent.completeTask, targetTaskIds: ['id0']),
    ]);
    await addTask('Đá bóng', DateTime(2026, 10, 22, 17));
    final ask = await h.handle('xong báo cáo tuần'); // Gemini chọn nhầm id0
    expect(ask, contains('Có phải'));
    expect(repo.store['id0']!.isCompleted, false);
    expect(await h.handle('không'), contains('chưa hoàn thành'));
    expect(repo.store['id0']!.isCompleted, false);
  });

  test('sửa chưa nói đổi gì → hỏi, không cập nhật rỗng', () async {
    final h = build([
      const AiCommand(intent: Intent.updateTask, targetTaskIds: ['id0']),
    ]);
    await addTask('Họp dự án', DateTime(2026, 10, 22, 9));
    final ask = await h.handle('sửa họp dự án');
    expect(ask, contains('thế nào'));
    expect(repo.store['id0']!.rescheduleCount, 0);
  });

  test('tạo trùng (cùng tên, cùng ngày) → hỏi trước khi tạo thêm', () async {
    final h = build([
      AiCommand(
          intent: Intent.createTask,
          title: 'Họp dự án',
          dueDate: DateTime(2026, 10, 22, 9)),
      AiCommand(
          intent: Intent.createTask,
          title: 'Họp dự án',
          dueDate: DateTime(2026, 10, 22, 14)),
    ]);
    await h.handle('mai 9h họp dự án');
    final ask = await h.handle('mai 2h chiều họp dự án');
    expect(ask, contains('đã có'));
    expect(repo.store.length, 1);
    await h.handle('có');
    expect(repo.store.length, 2);
  });

  test('completeTask đặt completedAt và hủy push', () async {
    final h = build([
      const AiCommand(intent: Intent.completeTask, targetTaskIds: ['id0']),
    ]);
    await repo.add(AppTask(
      id: '',
      title: 'x',
      dueDate: DateTime(2026, 10, 22),
      priority: Priority.low,
      notificationId: 4,
      createdAt: now,
    ));
    await h.handle('xong việc x');
    expect(repo.store['id0']!.isCompleted, true);
    expect(repo.store['id0']!.completedAt, now);
    expect(rem.cancelled, [4]);
  });

  test('hiệu suất không nói kỳ → hỏi lại, rồi làm theo kỳ được trả lời', () async {
    final h = build([]);
    final q = await h.handle('đánh giá hiệu suất');
    expect(q, contains('kỳ nào'));
    expect(h.awaitingClarification, true);
    expect(await h.handle('tuần này'), 'perf:week');
  });

  test('kỳ không hỗ trợ (tháng trước) → không tự đổi thành tháng này', () async {
    final h = build([]);
    final r = await h.handle('đánh giá hiệu suất tháng trước');
    expect(r, contains('hôm nay, tuần này, tháng này'));
    expect(await h.handle('tháng này'), 'perf:month');
  });

  test('kỳ chỉ nghe được ở cách nghe khác → hỏi xác nhận, không làm ngay', () async {
    final h = build([]);
    final r = await h.handle('đánh giá hiệu suất',
        alternatives: ['đánh giá hiệu suất tuần này']);
    expect(r, contains('Có phải'));
    expect(await h.handle('đúng'), 'perf:week');
  });

  test('askPerformance chuyển cho PerformanceService', () async {
    final h = build([
      const AiCommand(intent: Intent.askPerformance, period: 'week'),
    ]);
    expect(await h.handle('Tuần này tôi làm việc thế nào?'), 'perf:week');
  });

  test('alternatives từ nhận dạng giọng nói được chuyển cho bộ phân tích', () async {
    final parser = FakeParser([
      AiCommand(
          intent: Intent.createTask,
          title: 'Họp dự án',
          dueDate: DateTime(2026, 10, 22, 9)),
      const AiCommand(intent: Intent.chitchat, reply: 'Chào bạn!'),
    ]);
    final h = build([], parser);
    await h.handle('sáng mai 9h hộp dự án',
        alternatives: ['sáng mai 9h họp dự án']);
    await h.handle('xin chào');
    expect(parser.altsSeen, [
      ['sáng mai 9h họp dự án'],
      <String>[],
    ]);
  });
}