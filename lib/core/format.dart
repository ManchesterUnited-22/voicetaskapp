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
