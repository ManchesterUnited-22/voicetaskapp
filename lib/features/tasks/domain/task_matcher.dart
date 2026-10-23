import 'app_task.dart';

/// So khớp câu nói với tên việc, chịu được lỗi nhận dạng giọng nói:
/// bỏ dấu (hộp ≈ họp), bỏ từ lệnh ("xóa", "giúp tôi"...), cho phép sai 1 ký tự.
class TaskMatcher {
  static const _groups = <String, String>{
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };
  static final _foldMap = <String, String>{
    for (final e in _groups.entries)
      for (final ch in e.value.split('')) ch: e.key,
  };

  /// Từ lệnh / từ đệm / từ chỉ thời gian: không dùng để nhận ra tên việc (đã bỏ dấu).
  static const _stop = <String>{
    'xoa', 'bo', 'huy', 'sua', 'doi', 'chuyen', 'hoan', 'thanh', 'xong',
    'viec', 'cong', 'cai', 'lich', 'giup', 'toi', 'minh', 'oi', 'nhe', 'di',
    'nha', 'la', 'da', 'roi', 'hay', 'cho', 'voi', 'thi', 'ma', 'va', 'cua',
    'o', 'vao', 'luc', 'gio', 'h', 'hom', 'nay', 'mai', 'ngay', 'sang',
    'trua', 'chieu', 'tuan', 'thang', 'nam', 'sau', 'truoc', 'qua', 'kia',
    'do', 'nhung', 'cac', 'tat', 'ca', 'het', 'toan', 'mot', 'nua',
    'lai', 'them', 'tao', 'nhac', 'dat', 'den', 'tu', 'phut', 'khong',
    'co', 'phai', 'dung', 'vua', 'ay', 'nao', 'gi',
  };

  /// Chữ thường, bỏ dấu tiếng Việt.
  static String fold(String s) =>
      s.toLowerCase().split('').map((c) => _foldMap[c] ?? c).join();

  static List<String> tokens(String s) => fold(s)
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_stop.contains(w))
      .toList();

  /// Sai khác tối đa 1 ký tự (thêm / bớt / đổi) — dành cho từ đủ dài.
  static bool _lev1(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length > b.length) {
        i++;
      } else if (a.length < b.length) {
        j++;
      } else {
        i++;
        j++;
      }
    }
    edits += (a.length - i) + (b.length - j);
    return edits <= 1;
  }

  static bool _same(String a, String b) =>
      a == b || (a.length >= 4 && b.length >= 4 && _lev1(a, b));

  /// 0..1: câu nói nhắc tới bao nhiêu phần của tên việc (hoặc tên việc bao trùm câu nói).
  /// ≥ 0.6 coi như người dùng đã nói đúng việc này.
  static double score(String spoken, String title) {
    final tt = tokens(title);
    final st = tokens(spoken);
    if (tt.isEmpty || st.isEmpty) return 0;
    var hit = 0;
    for (final t in tt) {
      if (st.any((s) => _same(s, t))) hit++;
    }
    if (hit == 0) return 0;
    final titleCov = hit / tt.length;
    final spokenCov = hit / st.length;
    return titleCov > spokenCov ? titleCov : spokenCov;
  }

  static double bestScore(Iterable<String> spoken, String title) {
    var best = 0.0;
    for (final s in spoken) {
      final v = score(s, title);
      if (v > best) best = v;
    }
    return best;
  }

  /// Các việc gần giống nhất với (một trong các) câu nói, tốt nhất trước.
  static List<AppTask> search(Iterable<String> spoken, List<AppTask> pool,
      {int max = 3, double minScore = 0.5}) {
    final scored = <(AppTask, double)>[];
    for (final t in pool) {
      final v = bestScore(spoken, t.title);
      if (v >= minScore) scored.add((t, v));
    }
    scored.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      if (c != 0) return c;
      final la = tokens(a.$1.title).length, lb = tokens(b.$1.title).length;
      if (la != lb) return la.compareTo(lb); // tên ngắn gọn khớp hơn
      return a.$1.dueDate.compareTo(b.$1.dueDate);
    });
    return [for (final e in scored.take(max)) e.$1];
  }
}