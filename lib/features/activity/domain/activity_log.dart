import 'dart:async';
import 'dart:convert';

import '../../tasks/domain/task_repository.dart';
import 'activity_entry.dart';

class ActivityLog {
  final TaskRepository repo;
  final DateTime Function() clock;
  ActivityLog(this.repo, {this.clock = DateTime.now});

  static const maxMemory = 30;
  final _entries = <ActivityEntry>[]; // cũ → mới
  int version = 0; // tăng mỗi lần ghi (count không dùng được vì bị cắt ở maxMemory)

  /// Gọi 1 lần khi mở app: nạp nhật ký từ Firestore để "vừa dời việc nào" vẫn nhớ sau khi tắt app.
  Future<void> load() async {
    try {
      final rows = await repo.loadActivity(limit: maxMemory); // mới → cũ
      _entries
        ..clear()
        ..addAll(rows.map(ActivityEntry.fromMap).toList().reversed);
    } catch (_) {} // offline / lỗi mạng: dùng RAM
  }

  ActivityEntry record(
    String kind, {
    List<ActivityItem> items = const [],
    String source = 'voice',
    String? intent,
    String? rawText,
    String? summary,
    DateTime? at,
  }) {
    final t = at ?? clock();
    final e = ActivityEntry(
      id: '${t.microsecondsSinceEpoch}',
      at: t,
      kind: kind,
      source: source,
      intent: intent,
      rawText: rawText,
      summary: summary,
      items: items,
    );
    _entries.add(e);
    if (_entries.length > maxMemory) _entries.removeAt(0);
    version++;
    // Không await: ghi Firestore chạy nền, lỗi cũng không làm hỏng luồng chính.
    unawaited(repo.saveActivity(e.toMap()).catchError((_) {}));
    return e;
  }

  /// Hoàn tác: đánh dấu mục mutation gần nhất là đã hoàn tác, rồi ghi thêm 1 mục 'undo'.
  void markLastUndone(String label, {String source = 'voice'}) {
    final last = _entries.reversed
        .where((e) => e.isMutation && !e.undone)
        .firstOrNull;
    if (last != null) {
      last.undone = true;
      unawaited(repo.markActivityUndone(last.id).catchError((_) {}));
    }
    record('undo', summary: label, source: source);
  }

  /// Mutation gần nhất (theo loại nếu có) để trả lời "vừa dời việc nào?".
  ActivityEntry? lastMutation([String? kind]) => _entries.reversed
      .where((e) => e.isMutation && !e.undone && (kind == null || e.kind == kind))
      .firstOrNull;

  /// JSON gọn gửi cho Gemini (chỉ các thao tác đổi dữ liệu, chưa bị hoàn tác).
  String? recentJson({int take = 5}) {
    String iso(DateTime d) => d.toIso8601String().substring(0, 16);
    final list = _entries.reversed
        .where((e) => e.isMutation && !e.undone)
        .take(take)
        .map((r) => {
              'kind': r.kind,
              'at': iso(r.at),
              'items': r.items
                  .map((i) => {
                        'id': i.id,
                        'title': i.title,
                        if (i.from != null) 'from': iso(i.from!),
                        if (i.to != null) 'to': iso(i.to!),
                      })
                  .toList(),
            })
        .toList();
    return list.isEmpty ? null : jsonEncode(list);
  }
}