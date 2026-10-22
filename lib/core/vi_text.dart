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