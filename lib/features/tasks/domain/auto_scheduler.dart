import '../../../core/config.dart';
import 'app_task.dart';

class ScheduleResult {
  final DateTime start;

  /// true nếu khung giờ yêu cầu bị trùng và đã được dời sang khoảng trống kế tiếp.
  final bool adjusted;
  const ScheduleResult(this.start, {required this.adjusted});
}

/// Thuật toán Auto-Scheduling (mục 4.2): kiểm tra quỹ thời gian trống,
/// nếu trùng lịch thì chọn khoảng trống kế tiếp, không chồng chéo công việc.
/// Thuần Dart, không phụ thuộc Firebase → dễ kiểm thử.
class AutoScheduler {
  final int dayStartHour;
  final int dayEndHour;
  const AutoScheduler({
    this.dayStartHour = AppConfig.workDayStartHour,
    this.dayEndHour = AppConfig.workDayEndHour,
  });

  /// [requested] = null khi người dùng không nói giờ → lấy khung trống gần nhất từ [now].
  /// [existing] chỉ cần các task chưa hoàn thành; [ignoreTaskId] dùng khi dời lịch chính task đó.
  ScheduleResult findSlot({
    required DateTime? requested,
    required int durationMinutes,
    required List<AppTask> existing,
    required DateTime now,
    String? ignoreTaskId,
  }) {
    final busy = existing
        .where((t) => !t.isCompleted && t.id != ignoreTaskId)
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final dur = Duration(minutes: durationMinutes);

    var candidate = requested ?? _roundUp(now);
    final explicit = requested != null;
    if (!explicit) candidate = _clampToWorkHours(candidate, dur);

    // Giờ người dùng nói rõ được tôn trọng kể cả ngoài giờ làm việc;
    // chỉ khi phải dời mới ép vào giờ làm việc.
    var adjusted = false;
    for (var i = 0; i < 500; i++) {
      final end = candidate.add(dur);
      AppTask? clash;
      for (final t in busy) {
        if (candidate.isBefore(t.endDate) && t.dueDate.isBefore(end)) {
          clash = t;
          break;
        }
      }
      if (clash == null) {
        return ScheduleResult(candidate, adjusted: adjusted && explicit);
      }
      adjusted = true;
      candidate = _clampToWorkHours(clash.endDate, dur);
    }
    return ScheduleResult(candidate, adjusted: adjusted && explicit);
  }

  DateTime _roundUp(DateTime t) {
    final base = DateTime(t.year, t.month, t.day, t.hour, t.minute);
    final r = base.minute % 15;
    return r == 0 && t.second == 0
        ? base
        : base.add(Duration(minutes: 15 - r));
  }

  /// Ép về trong giờ làm việc: trước giờ mở → dời tới giờ mở;
  /// nếu kết thúc vượt giờ đóng → sang giờ mở ngày hôm sau.
  DateTime _clampToWorkHours(DateTime t, Duration dur) {
    var d = t;
    final open = DateTime(d.year, d.month, d.day, dayStartHour);
    final close = DateTime(d.year, d.month, d.day, dayEndHour);
    if (d.isBefore(open)) d = open;
    if (d.add(dur).isAfter(close)) {
      d = DateTime(d.year, d.month, d.day + 1, dayStartHour);
    }
    return d;
  }
}
