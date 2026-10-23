class ActivityItem {
  final String id;
  final String title;
  final DateTime? from; // giờ cũ
  final DateTime? to; // giờ mới
  const ActivityItem(this.id, this.title, {this.from, this.to});

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        if (from != null) 'from': from!.toIso8601String(),
        if (to != null) 'to': to!.toIso8601String(),
      };

  factory ActivityItem.fromMap(Map<String, dynamic> m) => ActivityItem(
        m['id'] as String,
        m['title'] as String,
        from: m['from'] == null ? null : DateTime.parse(m['from'] as String),
        to: m['to'] == null ? null : DateTime.parse(m['to'] as String),
      );
}

class ActivityEntry {
  /// Các loại làm thay đổi dữ liệu (Gemini cần biết để hiểu "những việc đó").
  static const mutations = {'create', 'move', 'edit', 'delete', 'complete', 'reopen'};

  final String id;
  final DateTime at;
  final String kind; // create|move|edit|delete|complete|reopen|undo|interaction
  final String source; // voice | ui | system
  final String? intent; // với kind == 'interaction': queryTasks, chitchat, ...
  final String? rawText; // câu người dùng nói/gõ (nếu có)
  final String? summary; // câu trợ lý trả lời / mô tả ngắn
  final List<ActivityItem> items;
  bool undone;

  ActivityEntry({
    required this.id,
    required this.at,
    required this.kind,
    this.source = 'voice',
    this.intent,
    this.rawText,
    this.summary,
    this.items = const [],
    this.undone = false,
  });

  bool get isMutation => mutations.contains(kind);

  Map<String, dynamic> toMap() => {
        'id': id,
        'at': at, // repo sẽ đổi sang Timestamp
        'kind': kind,
        'source': source,
        if (intent != null) 'intent': intent,
        if (rawText != null) 'rawText': rawText,
        if (summary != null) 'summary': summary,
        'items': items.map((e) => e.toMap()).toList(),
        'undone': undone,
      };

  factory ActivityEntry.fromMap(Map<String, dynamic> m) => ActivityEntry(
        id: m['id'] as String,
        at: m['at'] as DateTime,
        kind: m['kind'] as String,
        source: (m['source'] as String?) ?? 'voice',
        intent: m['intent'] as String?,
        rawText: m['rawText'] as String?,
        summary: m['summary'] as String?,
        items: ((m['items'] as List?) ?? const [])
            .map((e) => ActivityItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        undone: (m['undone'] as bool?) ?? false,
      );
}