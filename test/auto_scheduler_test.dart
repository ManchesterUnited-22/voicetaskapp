import 'package:flutter_test/flutter_test.dart';
import 'package:voice_task_app/features/tasks/domain/app_task.dart';
import 'package:voice_task_app/features/tasks/domain/auto_scheduler.dart';

AppTask task(String id, DateTime due, {int dur = 60, bool done = false}) =>
    AppTask(
      id: id,
      title: id,
      dueDate: due,
      priority: Priority.medium,
      notificationId: 0,
      createdAt: DateTime(2026, 10, 1),
      durationMinutes: dur,
      isCompleted: done,
    );

void main() {
  const s = AutoScheduler();
  final now = DateTime(2026, 10, 21, 17, 46);

  test('giữ nguyên giờ khi không trùng', () {
    final r = s.findSlot(
      requested: DateTime(2026, 10, 22, 9),
      durationMinutes: 60,
      existing: [task('a', DateTime(2026, 10, 22, 14))],
      now: now,
    );
    expect(r.start, DateTime(2026, 10, 22, 9));
    expect(r.adjusted, false);
  });

  test('trùng lịch → dời sang khoảng trống kế tiếp (UC-01 luồng ngoại lệ)', () {
    final r = s.findSlot(
      requested: DateTime(2026, 10, 22, 9),
      durationMinutes: 60,
      existing: [task('a', DateTime(2026, 10, 22, 9))],
      now: now,
    );
    expect(r.start, DateTime(2026, 10, 22, 10));
    expect(r.adjusted, true);
  });

  test('trùng một phần cũng bị coi là trùng', () {
    final r = s.findSlot(
      requested: DateTime(2026, 10, 22, 9, 30),
      durationMinutes: 60,
      existing: [task('a', DateTime(2026, 10, 22, 9))],
      now: now,
    );
    expect(r.start, DateTime(2026, 10, 22, 10));
  });

  test('xếp nối tiếp qua nhiều task liền kề', () {
    final r = s.findSlot(
      requested: DateTime(2026, 10, 22, 9),
      durationMinutes: 60,
      existing: [
        task('a', DateTime(2026, 10, 22, 9)),
        task('b', DateTime(2026, 10, 22, 10)),
      ],
      now: now,
    );
    expect(r.start, DateTime(2026, 10, 22, 11));
  });

  test('bỏ qua task đã hoàn thành và task bị loại trừ', () {
    final r = s.findSlot(
      requested: DateTime(2026, 10, 22, 9),
      durationMinutes: 60,
      existing: [
        task('done', DateTime(2026, 10, 22, 9), done: true),
        task('self', DateTime(2026, 10, 22, 9)),
      ],
      now: now,
      ignoreTaskId: 'self',
    );
    expect(r.start, DateTime(2026, 10, 22, 9));
    expect(r.adjusted, false);
  });

  test('hết giờ làm việc → sang giờ mở cửa ngày hôm sau', () {
    final r = s.findSlot(
      requested: DateTime(2026, 10, 22, 21),
      durationMinutes: 60,
      existing: [task('a', DateTime(2026, 10, 22, 21))],
      now: now,
    );
    expect(r.start, DateTime(2026, 10, 23, 7));
  });

  test('không nói giờ → khung trống gần nhất làm tròn 15 phút', () {
    final r = s.findSlot(
      requested: null,
      durationMinutes: 30,
      existing: const [],
      now: DateTime(2026, 10, 21, 10, 7),
    );
    expect(r.start, DateTime(2026, 10, 21, 10, 15));
    expect(r.adjusted, false);
  });

  test('không nói giờ, ngoài giờ làm việc → sáng hôm sau', () {
    final r = s.findSlot(
      requested: null,
      durationMinutes: 60,
      existing: const [],
      now: DateTime(2026, 10, 21, 22, 30),
    );
    expect(r.start, DateTime(2026, 10, 22, 7));
  });
}
