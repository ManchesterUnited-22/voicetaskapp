import 'package:flutter_test/flutter_test.dart';
import 'package:voice_task_app/features/analytics/domain/performance_metrics.dart';
import 'package:voice_task_app/features/tasks/domain/app_task.dart';

AppTask t(DateTime due, {DateTime? doneAt, int resched = 0}) => AppTask(
      id: due.toIso8601String(),
      title: 't',
      dueDate: due,
      priority: Priority.medium,
      notificationId: 0,
      createdAt: DateTime(2026, 10, 1),
      isCompleted: doneAt != null,
      completedAt: doneAt,
      rescheduleCount: resched,
    );

void main() {
  final now = DateTime(2026, 10, 21, 20);

  test('tính tỷ lệ đúng hạn, quá hạn, khung giờ hiệu quả', () {
    final tasks = [
      t(DateTime(2026, 10, 19, 9), doneAt: DateTime(2026, 10, 19, 8, 50)),
      t(DateTime(2026, 10, 19, 10), doneAt: DateTime(2026, 10, 19, 9, 59)),
      t(DateTime(2026, 10, 20, 16), doneAt: DateTime(2026, 10, 20, 18)), // trễ
      t(DateTime(2026, 10, 21, 17), resched: 2), // quá hạn, chưa xong
    ];
    final m = const PerformanceCalculator().compute(tasks, now);
    expect(m.total, 4);
    expect(m.completedOnTime, 2);
    expect(m.completedLate, 1);
    expect(m.overdue, 1);
    expect(m.completionRate, 50);
    expect(m.overdueRate, 25);
    expect(m.peakProductiveHours, '08:00-10:00'); // hòa 1-1 giữa 9h và 10h → lấy khung đầu tiên
    expect(m.rescheduleCount, 2);
    expect(m.activeDays, 3);
    expect(m.hasEnoughData, true);
  });

  test('chưa đủ 3 ngày dữ liệu', () {
    final m = const PerformanceCalculator()
        .compute([t(DateTime(2026, 10, 21, 9), doneAt: DateTime(2026, 10, 21, 9))], now);
    expect(m.hasEnoughData, false);
  });
}
