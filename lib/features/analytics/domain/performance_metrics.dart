import '../../../core/config.dart';
import '../../tasks/domain/app_task.dart';

class PerformanceMetrics {
  final int total;
  final int completedOnTime;
  final int completedLate;
  final int overdue; // chưa hoàn thành và đã quá hạn
  final double completionRate; // % hoàn thành đúng hạn
  final double overdueRate; // % quá hạn (chưa xong)
  final String? peakProductiveHours; // vd "09:00-11:00"
  final String? weakestHours; // khung giờ hay trễ nhất
  final int rescheduleCount;
  final int activeDays;

  const PerformanceMetrics({
    required this.total,
    required this.completedOnTime,
    required this.completedLate,
    required this.overdue,
    required this.completionRate,
    required this.overdueRate,
    required this.peakProductiveHours,
    required this.weakestHours,
    required this.rescheduleCount,
    required this.activeDays,
  });

  bool get hasEnoughData => activeDays >= AppConfig.minDaysForCoaching;

  Map<String, dynamic> toJson() => {
        'tongSoViec': total,
        'hoanThanhDungHan': completedOnTime,
        'hoanThanhTre': completedLate,
        'quaHanChuaXong': overdue,
        'tyLeHoanThanhDungHanPhanTram': completionRate.round(),
        'tyLeQuaHanPhanTram': overdueRate.round(),
        'khungGioHieuQuaNhat': peakProductiveHours,
        'khungGioHayTreNhat': weakestHours,
        'soLanDoiLich': rescheduleCount,
        'soNgayCoDuLieu': activeDays,
      };
}

/// Performance Analytics Module (UC-02): tính các chỉ số từ lịch sử tasks.
class PerformanceCalculator {
  const PerformanceCalculator();

  PerformanceMetrics compute(List<AppTask> tasks, DateTime now) {
    var onTime = 0, late = 0, overdue = 0, resched = 0;
    final doneByWindow = <int, int>{};
    final lateByWindow = <int, int>{};
    final days = <String>{};

    for (final t in tasks) {
      days.add('${t.dueDate.year}-${t.dueDate.month}-${t.dueDate.day}');
      resched += t.rescheduleCount;
      final window = t.dueDate.hour ~/ 2 * 2; // cửa sổ 2 giờ
      if (t.isCompleted) {
        final doneAt = t.completedAt ?? t.dueDate;
        if (!doneAt.isAfter(t.dueDate)) {
          onTime++;
          doneByWindow[window] = (doneByWindow[window] ?? 0) + 1;
        } else {
          late++;
          lateByWindow[window] = (lateByWindow[window] ?? 0) + 1;
        }
      } else if (t.dueDate.isBefore(now)) {
        overdue++;
        lateByWindow[window] = (lateByWindow[window] ?? 0) + 1;
      }
    }

    final total = tasks.length;
    double pct(int n) => total == 0 ? 0 : n * 100 / total;
    return PerformanceMetrics(
      total: total,
      completedOnTime: onTime,
      completedLate: late,
      overdue: overdue,
      completionRate: pct(onTime),
      overdueRate: pct(overdue),
      peakProductiveHours: _top(doneByWindow),
      weakestHours: _top(lateByWindow),
      rescheduleCount: resched,
      activeDays: days.length,
    );
  }

  String? _top(Map<int, int> m) {
    if (m.isEmpty) return null;
    final best = m.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    String h(int x) => '${x.toString().padLeft(2, '0')}:00';
    return '${h(best)}-${h(best + 2)}';
  }
}
