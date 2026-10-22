import '../../../core/config.dart';
import '../../ai_engine/data/gemini_service.dart';
import '../../tasks/domain/task_repository.dart';
import '../domain/performance_metrics.dart';

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
    final tasks = await repo.getBetween(from, to);
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
    await repo.saveAnalytics({
      'period': p,
      'completionRate': metrics.completionRate,
      'overdueRate': metrics.overdueRate,
      'peakProductiveHours': metrics.peakProductiveHours ?? '',
      'aiFeedbackSummary': feedback,
    });
    return CoachReport(metrics, feedback, true);
  }

  /// Nhận xét cuối ngày (UC-02 "định kỳ cuối ngày"): sau 20h, mỗi ngày một lần, gửi qua push.
  /// Trả về nội dung đã gửi, hoặc null nếu chưa đến lúc / chưa đủ dữ liệu.
  Future<String?> maybeDailyCoach(
    Future<void> Function(String title, String body) push, {
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now();
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
