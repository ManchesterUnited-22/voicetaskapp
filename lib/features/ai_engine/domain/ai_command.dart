import '../../tasks/domain/app_task.dart';

enum Intent {
  createTask,
  updateTask,
  deleteTask,
  completeTask,
  queryTasks,
  askPerformance,
  recallAction, // hỏi lại về thao tác vừa làm ("vừa dời những việc nào?")
  chitchat,
  needClarification,
  unknown,
}

Intent intentFromString(String? s) => Intent.values.firstWhere(
      (i) => i.name == s,
      orElse: () => Intent.unknown,
    );

/// Bộ phân tích câu lệnh (Gemini ở runtime, giả lập khi kiểm thử).
abstract class CommandParser {
  Future<AiCommand> parse({
    required String text,
    required List<AppTask> tasks,
    DateTime? now,
    String? pendingContext,

    /// Nhật ký các thao tác gần đây (JSON) để hiểu "những việc đó / việc vừa dời".
    String? recentActions,

    /// Các cách nghe khác của máy nhận dạng giọng nói cho câu [text].
    List<String> alternatives = const [],
  });
}

/// Kết quả JSON do Gemini trả về (Bảng 1, bước 4-5): {intent, title, dueDate, priority, ...}
class AiCommand {
  final Intent intent;
  final String? title;
  final DateTime? dueDate;
  final Priority? priority;
  final int? durationMinutes;
  final String? recurrenceRule;

  /// Id các task được nhắm tới (sửa/xóa/hoàn thành, kể cả hàng loạt).
  final List<String> targetTaskIds;

  /// Khoảng thời gian cho queryTasks.
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  /// day | week | month | year — cho askPerformance.
  final String? period;

  /// overdue | upcoming | all — cho queryTasks.
  final String? queryFilter;

  /// Câu trả lời xã giao khi intent = chitchat.
  final String? reply;

  /// true khi người dùng nói rõ "tất cả / hết / toàn bộ" (thao tác hàng loạt).
  final bool isBatch;

  /// Câu hỏi làm rõ khi intent = needClarification.
  final String? question;

  /// Khi bản chép lời nghe không hợp lý: câu hoàn chỉnh theo cách hiểu đã sửa.
  /// App sẽ hỏi lại người dùng trước khi thực hiện.
  final String? doubtCorrected;

  /// move | edit | delete | complete | create | any — cho recallAction.
  final String? actionKind;

  bool get hasDoubt => (doubtCorrected ?? '').isNotEmpty;

  const AiCommand({
    required this.intent,
    this.title,
    this.dueDate,
    this.priority,
    this.durationMinutes,
    this.recurrenceRule,
    this.targetTaskIds = const [],
    this.rangeStart,
    this.rangeEnd,
    this.period,
    this.queryFilter,
    this.reply,
    this.isBatch = false,
    this.question,
    this.doubtCorrected,
    this.actionKind,
  });

  static DateTime? _dt(dynamic v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

  factory AiCommand.fromJson(Map<String, dynamic> j) {
    final pr = j['priority'] as String?;
    final doubt = j['doubt'];
    return AiCommand(
      intent: intentFromString(j['intent'] as String?),
      title: (j['title'] as String?)?.trim(),
      dueDate: _dt(j['dueDate']),
      priority: pr == null ? null : priorityFromString(pr),
      durationMinutes: (j['durationMinutes'] as num?)?.toInt(),
      recurrenceRule: j['recurrenceRule'] as String?,
      targetTaskIds:
          ((j['targetTaskIds'] as List?) ?? const []).whereType<String>().toList(),
      rangeStart: _dt(j['rangeStart']),
      rangeEnd: _dt(j['rangeEnd']),
      period: j['period'] as String?,
      question: j['question'] as String?,
      queryFilter: j['queryFilter'] as String?,
      reply: (j['reply'] as String?)?.trim(),
      isBatch: j['isBatch'] == true,
      actionKind: j['actionKind'] as String?,
      doubtCorrected:
          doubt is Map ? (doubt['corrected'] as String?)?.trim() : null,
    );
  }
}