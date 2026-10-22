import 'package:intl/intl.dart';

/// "9h", "9h30", "14h05"
String formatTimeVi(DateTime d) {
  final m = d.minute;
  return m == 0 ? '${d.hour}h' : '${d.hour}h${m.toString().padLeft(2, '0')}';
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "hôm nay", "ngày mai", hoặc "dd/MM"
String formatDayVi(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'hôm nay';
  if (diff == 1) return 'ngày mai';
  if (diff == -1) return 'hôm qua';
  return DateFormat('dd/MM').format(d);
}

String formatDateTimeVi(DateTime d, DateTime now) =>
    '${formatTimeVi(d)} ${formatDayVi(d, now)}';

/// Mô tả một khoảng thời gian [from, to) để đọc cho người dùng, ví dụ:
/// "hôm nay", "ngày mai", "ngày 25/10", "từ 14h đến 17h hôm nay",
/// "từ ngày 20/10 đến ngày 26/10".
String formatRangeVi(DateTime from, DateTime to, DateTime now) {
  final last = to.subtract(const Duration(minutes: 1));
  final fromMidnight = from.hour == 0 && from.minute == 0;
  final toMidnight = to.hour == 0 && to.minute == 0;
  final wholeDays =
      fromMidnight && (toMidnight || (to.hour == 23 && to.minute >= 59));

  if (isSameDay(from, last)) {
    final day = formatDayVi(from, now);
    final dayText = day.contains('/') ? 'ngày $day' : day;
    if (wholeDays) return dayText;
    return 'từ ${formatTimeVi(from)} đến ${formatTimeVi(to)} $dayText';
  }
  String d(DateTime x) {
    final s = formatDayVi(x, now);
    return s.contains('/') ? 'ngày $s' : s;
  }

  if (wholeDays) return 'từ ${d(from)} đến ${d(last)}';
  return 'từ ${formatTimeVi(from)} ${d(from)} đến ${formatTimeVi(to)} ${d(to)}';
}