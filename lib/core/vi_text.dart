import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;

/// Các từ tiếng Anh không trùng với từ tiếng Việt không dấu, dùng để nhận ra
/// câu trả lời của mô hình bị lỡ sang tiếng Anh.
const _englishWords = <String>{
  'the', 'and', 'you', 'your', 'are', 'have', 'has', 'will', 'any', 'for',
  'with', 'this', 'there', 'today', 'tomorrow', 'task', 'tasks', 'schedule',
  'scheduled', 'nothing', 'hello', 'please', 'sorry', 'reminder', 'meeting',
  'would', 'could', 'should', 'what', 'when', 'which', 'help', 'sure',
};

final _viDiacritics = RegExp(
    r'[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ]',
    caseSensitive: false);

/// true nếu văn bản trông như tiếng Việt (hoặc quá ngắn để kết luận).
bool looksVietnamese(String s) {
  final words = RegExp(r"[A-Za-z']+")
      .allMatches(s.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
  final hits = words.where(_englishWords.contains).length;
  if (hits >= 2) return false;
  if (hits == 1 && !_viDiacritics.hasMatch(s)) return false;
  return true;
}

/// Trả về [text] nếu là tiếng Việt, ngược lại trả về [fallback].
String vietnameseOr(String? text, String fallback) {
  final t = text?.trim() ?? '';
  return t.isNotEmpty && looksVietnamese(t) ? t : fallback;
}

/// Đổi mọi lỗi (thường là tiếng Anh của hệ thống) thành câu tiếng Việt cho người dùng.
String friendlyError(Object e) {
  if (e is TimeoutException) {
    return 'Hệ thống phản hồi quá chậm, bạn thử lại sau nhé.';
  }
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return 'Bạn không có quyền truy cập dữ liệu này.';
      case 'unavailable':
      case 'network-request-failed':
        return 'Không có kết nối mạng. Bạn kiểm tra lại rồi thử nhé.';
      case 'unauthenticated':
        return 'Phiên đăng nhập đã hết hạn, bạn đăng nhập lại nhé.';
    }
    return 'Không tải được dữ liệu. Bạn thử lại sau nhé.';
  }
  final s = e.toString();
  // GeminiException và các lỗi tự định nghĩa đã là tiếng Việt.
  if (s.isNotEmpty && _viDiacritics.hasMatch(s) && looksVietnamese(s)) return s;
  final low = s.toLowerCase();
  if (low.contains('socket') ||
      low.contains('host lookup') ||
      low.contains('clientexception') ||
      low.contains('network')) {
    return 'Không có kết nối mạng. Bạn kiểm tra lại rồi thử nhé.';
  }
  return 'Đã có lỗi xảy ra. Bạn thử lại sau nhé.';
}

// ───────────── Nhận diện câu hỏi "hiệu suất <kỳ>" ─────────────

/// Nhãn đọc lên cho từng kỳ.
const perfPeriodLabel = <String, String>{
  'day': 'hôm nay',
  'week': 'tuần này',
  'month': 'tháng này',
  'year': 'năm nay',
};

class PerfMatch {
  final String period; // day | week | month | year

  /// true: từ chỉ kỳ nghe đúng chuẩn. false: chỉ là nghe gần giống
  /// (vd "thắng" thay vì "tháng") → phải hỏi lại người dùng.
  final bool exact;
  const PerfMatch(this.period, this.exact);
}

/// Nhận ra câu hỏi "đánh giá hiệu suất <kỳ>". Trả về null nếu không phải
/// (hoặc không có từ chỉ kỳ → để Gemini xử lý).
PerfMatch? matchPerformance(String text) {
  final t = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final m = RegExp(r'(hiệu|năng) (suất|xuất|sút|sức|suốt)').firstMatch(t);
  if (m == null) return null;

  const exact = <String, String>{
    'tháng': 'month', 'tuần': 'week', 'năm': 'year', 'hôm': 'day', 'ngày': 'day',
  };
  const near = <String, String>{
    'thắng': 'month', 'thấp': 'month', 'thán': 'month', 'thang': 'month',
    'thăng': 'month', 'thản': 'month',
    'tuấn': 'week', 'tuân': 'week', 'tuận': 'week',
    'nằm': 'year', 'nấm': 'year', 'nắm': 'year',
  };
  final tail = t.substring(m.end).trim();
  if (tail.isNotEmpty) {
    for (final w in tail.split(' ').take(5)) {
      if (exact[w] != null) return PerfMatch(exact[w]!, true);
      if (near[w] != null) return PerfMatch(near[w]!, false);
    }
  }
  // Nói đảo ("tháng này đánh giá hiệu suất"): chỉ tin các từ viết đúng.
  for (final w in t.substring(0, m.start).split(' ')) {
    if (exact[w] != null) return PerfMatch(exact[w]!, true);
  }
  return null;
}