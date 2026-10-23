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

  test('deleteTask hàng loạt', () async {
    final h = build([
      const AiCommand(intent: Intent.deleteTask, targetTaskIds: ['id0', 'id1']),
    ]);
    for (final n in ['x', 'y', 'z']) {
      await repo.add(AppTask(
        id: '',
        title: n,
        dueDate: DateTime(2026, 10, 10),
        priority: Priority.low,
        notificationId: 2,
        createdAt: now,
      ));
    }
    final reply = await h.handle('xóa tất cả việc quá hạn');
    expect(reply, 'Đã xóa 2 công việc.');
    expect(repo.store.keys, ['id2']);
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