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

enum PerfIssue {
  /// Nghe được kỳ cụ thể (day | week | month | year).
  none,

  /// Có nói "hiệu suất" nhưng KHÔNG nghe thấy kỳ nào → phải hỏi lại, không tự đoán.
  missing,

  /// Có nói kỳ mà app không hỗ trợ ("tháng trước", "hôm qua", "tháng 9",
  /// "từ ngày 1 đến ngày 5"...) → không được tự đổi thành kỳ hiện tại.
  unsupported,
}

class PerfMatch {
  final String? period; // day | week | month | year (null nếu issue != none)

  /// true: từ chỉ kỳ nghe đúng chuẩn. false: chỉ là nghe gần giống
  /// (vd "thắng" thay vì "tháng") → phải hỏi lại người dùng.
  final bool exact;
  final PerfIssue issue;
  const PerfMatch(this.period, this.exact) : issue = PerfIssue.none;
  const PerfMatch.missing()
      : period = null,
        exact = false,
        issue = PerfIssue.missing;
  const PerfMatch.unsupported()
      : period = null,
        exact = false,
        issue = PerfIssue.unsupported;
}

const _exactPeriod = <String, String>{
  'tháng': 'month', 'tuần': 'week', 'năm': 'year', 'hôm': 'day', 'ngày': 'day',
};
const _nearPeriod = <String, String>{
  'thắng': 'month', 'thấp': 'month', 'thán': 'month', 'thang': 'month',
  'thăng': 'month', 'thản': 'month',
  'tuấn': 'week', 'tuân': 'week', 'tuận': 'week',
  'nằm': 'year', 'nấm': 'year', 'nắm': 'year',
};

/// Từ làm lệch kỳ: "tuần TRƯỚC", "hôm QUA", "tháng NGOÁI", "tuần TỚI"...
const _shiftWords = <String>{
  'trước', 'qua', 'rồi', 'sau', 'ngoái', 'kia', 'mai', 'kế', 'tới', 'vừa',
  'từ', 'đến',
};

/// Số đứng ngay trước từ chỉ kỳ: "HAI tuần", "VÀI tháng".
const _countWords = <String>{
  'hai', 'ba', 'bốn', 'sáu', 'bảy', 'tám', 'chín', 'mười', 'mấy', 'vài',
};

final _perfRe = RegExp(r'(hiệu|năng) (suất|xuất|sút|sức|suốt)');
final _digitRe = RegExp(r'\d');

String _normVi(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Câu có chứa kỳ mà app KHÔNG hỗ trợ (số/ngày cụ thể, tuần trước, hôm qua, khoảng từ-đến...).
/// App chỉ đánh giá TRỌN kỳ hiện tại: hôm nay, tuần này, tháng này, năm nay.
bool _outOfScope(List<String> words) {
  if (words.any(_digitRe.hasMatch)) return true;
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (_shiftWords.contains(w)) return true;
    // "hôm" chỉ hợp lệ khi đi với "nay".
    if (w == 'hôm' && (i + 1 >= words.length || words[i + 1] != 'nay')) {
      // "ngày hôm nay" vẫn hợp lệ vì đã xét "hôm nay"; còn lại ("hôm qua"...) là ngoài phạm vi.
      return true;
    }
    final isPeriod = _exactPeriod.containsKey(w) || _nearPeriod.containsKey(w);
    if (isPeriod && i > 0 && _countWords.contains(words[i - 1])) return true;
  }
  return false;
}

PerfMatch? _findPeriod(Iterable<String> words, {required bool allowNear}) {
  for (final w in words) {
    if (_exactPeriod[w] != null) return PerfMatch(_exactPeriod[w]!, true);
    if (allowNear && _nearPeriod[w] != null) {
      return PerfMatch(_nearPeriod[w]!, false);
    }
  }
  return null;
}

/// Nhận ra câu hỏi "đánh giá hiệu suất <kỳ>".
/// - null: câu không nói về hiệu suất (để Gemini xử lý).
/// - issue == missing: có nói hiệu suất nhưng chưa nghe thấy kỳ → phải hỏi lại.
/// - issue == unsupported: kỳ ngoài 4 kỳ hỗ trợ → báo và hỏi lại.
PerfMatch? matchPerformance(String text) {
  final t = _normVi(text);
  final m = _perfRe.firstMatch(t);
  if (m == null) return null;
  final words = t.split(' ');
  if (_outOfScope(words)) return const PerfMatch.unsupported();

  final tail = t.substring(m.end).trim();
  if (tail.isNotEmpty) {
    final hit = _findPeriod(tail.split(' ').take(5), allowNear: true);
    if (hit != null) return hit;
  }
  // Nói đảo ("tháng này đánh giá hiệu suất"): chỉ tin các từ viết đúng.
  final head = t.substring(0, m.start).trim();
  if (head.isNotEmpty) {
    final hit = _findPeriod(head.split(' '), allowNear: false);
    if (hit != null) return hit;
  }
  return const PerfMatch.missing();
}

/// Nhận ra kỳ trong CÂU TRẢ LỜI cho câu hỏi "bạn muốn xem kỳ nào?" (không cần nói lại "hiệu suất").
/// Trả về null nếu câu trả lời không nhắc kỳ nào (coi là lệnh mới).
PerfMatch? matchPeriodAnswer(String text) {
  final t = _normVi(text);
  if (t.isEmpty) return null;
  final words = t.split(' ');
  if (_outOfScope(words)) return const PerfMatch.unsupported();
  return _findPeriod(words.take(5), allowNear: true);
}