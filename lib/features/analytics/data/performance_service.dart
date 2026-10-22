import '../../../core/config.dart';
import '../../ai_engine/data/gemini_service.dart';
import '../../tasks/domain/task_repository.dart';
import '../domain/performance_metrics.dart';
import '../../tasks/domain/app_task.dart';
class CoachReport {
  final PerformanceMetrics metrics;
  final String feedback;
  final bool enoughData;
  const CoachReport(this.metrics, this.feedback, this.enoughData);
}

/// AI Productivity Coach (UC-02, mục 4.3).
class PerformanceService {
  final TaskRepository repo;
  final GeminiService gemini;
  final PerformanceCalculator calculator;
  PerformanceService(this.repo, this.gemini,
      {this.calculator = const PerformanceCalculator()});

  static const periods = {
    'day': 'hôm nay',
    'week': 'tuần này',
    'month': 'tháng này',
    'year': 'năm nay',
  };

  (DateTime, DateTime) rangeFor(String period, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'day':
        return (today, today.add(const Duration(days: 1)));
      case 'month':
        return (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
      case 'year':
        return (DateTime(now.year), DateTime(now.year + 1));
      case 'week':
      default:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return (monday, monday.add(const Duration(days: 7)));
    }
  }

  Future<CoachReport> generate(String period, {DateTime? now}) async {
    final n = now ?? DateTime.now();
    final p = periods.containsKey(period) ? period : 'week';
    final (from, to) = rangeFor(p, n);
    final tasks = AppConfig.demoPerformance ? _demoTasks(n) : await repo.getBetween(from, to);
    final metrics = calculator.compute(tasks, n);

    if (!metrics.hasEnoughData) {
      return CoachReport(
        metrics,
        'Mình cần dữ liệu của ít nhất ${AppConfig.minDaysForCoaching} ngày để phân tích. '
        'Bạn dùng ứng dụng thêm vài ngày nữa nhé!',
        false,
      );
    }

    String feedback;
    try {
      feedback = await gemini.coach(metrics, periods[p]!);
    } catch (_) {
      feedback = _fallback(metrics, periods[p]!);
    }
        if (!AppConfig.demoPerformance) {
      await repo.saveAnalytics({
        'period': p,
        'completionRate': metrics.completionRate,
        'overdueRate': metrics.overdueRate,
        'peakProductiveHours': metrics.peakProductiveHours ?? '',
        'aiFeedbackSummary': feedback,
      });
    }
    return CoachReport(metrics, feedback, true);
  }

  /// Nhận xét cuối ngày (UC-02 "định kỳ cuối ngày"): sau 20h, mỗi ngày một lần, gửi qua push.
  /// Trả về nội dung đã gửi, hoặc null nếu chưa đến lúc / chưa đủ dữ liệu.
  Future<String?> maybeDailyCoach(
    Future<void> Function(String title, String body) push, {
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now();
        if (AppConfig.demoPerformance) return null; // không gửi push giả
    if (n.hour < AppConfig.dailyCoachHour) return null;
    final last = await repo.getLastDailyCoach();
    if (last != null &&
        last.year == n.year && last.month == n.month && last.day == n.day) {
      return null;
    }
    // Phân tích theo tuần (đủ dữ liệu hơn một ngày) nhưng đánh dấu là nhận xét ngày.
    final r = await generate('week', now: n);
    if (!r.enoughData) return null;
    await push('🧠 Nhận xét cuối ngày', r.feedback);
    await repo.setLastDailyCoach(n);
    return r.feedback;
  }
    /// Dữ liệu mẫu trải 5 ngày gần nhất, dùng chung cho mọi kỳ (ngày/tuần/tháng/năm).
  List<AppTask> _demoTasks(DateTime n) {
    var i = 0;
    AppTask t(int daysAgo, int hour, String title,
        {int? doneAfterMin, int resched = 0}) {
      final due = DateTime(n.year, n.month, n.day - daysAgo, hour);
      return AppTask(
        id: 'demo${i++}',
        title: title,
        dueDate: due,
        priority: Priority.medium,
        notificationId: 9000 + i,
        createdAt: due.subtract(const Duration(days: 1)),
        isCompleted: doneAfterMin != null,
        completedAt:
            doneAfterMin == null ? null : due.add(Duration(minutes: doneAfterMin)),
        rescheduleCount: resched,
      );
    }

    return [
      t(4, 8, 'Họp nhóm đồ án', doneAfterMin: -10),
      t(4, 14, 'Viết báo cáo thực tập', doneAfterMin: 90, resched: 1),
      t(3, 9, 'Học API Gemini', doneAfterMin: -5),
      t(3, 15, 'Làm bài tập đồ họa', doneAfterMin: 120, resched: 1),
      t(3, 20, 'Ôn tiếng Anh', doneAfterMin: -15),
      t(2, 8, 'Họp dự án FPT', doneAfterMin: -20),
      t(2, 9, 'Sửa lỗi voice chat', doneAfterMin: 0),
      t(2, 14, 'Nộp báo cáo tuần', resched: 2), // quá hạn, chưa xong
      t(1, 9, 'Test chức năng nhắc việc', doneAfterMin: -5),
      t(1, 15, 'Cập nhật slide', doneAfterMin: 75),
      t(0, 8, 'Tập thể dục', doneAfterMin: -10),
      t(0, 22, 'Chuẩn bị bài mai'), // sắp tới hạn
    ];
  }
  String _fallback(PerformanceMetrics m, String label) {
    final sb = StringBuffer(
        '$label bạn hoàn thành đúng hạn ${m.completionRate.round()}% công việc');
    if (m.overdue > 0) sb.write(', còn ${m.overdue} việc đang quá hạn');
    sb.write('.');
    if (m.peakProductiveHours != null) {
      sb.write(' Khung giờ hiệu quả nhất của bạn là ${m.peakProductiveHours}.');
    }
    return sb.toString();
  }
}
