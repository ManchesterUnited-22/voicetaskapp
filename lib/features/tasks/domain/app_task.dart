import 'package:cloud_firestore/cloud_firestore.dart';

enum Priority { high, medium, low }

Priority priorityFromString(String? s) => Priority.values.firstWhere(
      (p) => p.name == s,
      orElse: () => Priority.medium,
    );

/// Công việc — ánh xạ users/{userId}/tasks/{taskId} (Bảng 3 trong báo cáo).
/// Bổ sung so với báo cáo: durationMinutes (để phát hiện trùng khoảng giờ),
/// completedAt và rescheduleCount (để AI Coach phân tích).
class AppTask {
  final String id;
  final String title;
  final DateTime dueDate;
  final Priority priority;
  final bool isCompleted;
  final bool isRecurring;
  final String? recurrenceRule; // daily | weekly
  final int notificationId;
  final DateTime createdAt;
  final int durationMinutes;
  final DateTime? completedAt;
  final int rescheduleCount;

  const AppTask({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.priority,
    required this.notificationId,
    required this.createdAt,
    this.isCompleted = false,
    this.isRecurring = false,
    this.recurrenceRule,
    this.durationMinutes = 60,
    this.completedAt,
    this.rescheduleCount = 0,
  });

  DateTime get endDate => dueDate.add(Duration(minutes: durationMinutes));

  bool isOverdue(DateTime now) => !isCompleted && dueDate.isBefore(now);

  /// Lần lặp kế tiếp (daily/weekly) sau khi hoàn thành; null nếu không lặp.
  AppTask? nextOccurrence(String newId, int newNotificationId) {
    if (!isRecurring) return null;
    final step = switch (recurrenceRule) {
      'daily' => const Duration(days: 1),
      'weekly' => const Duration(days: 7),
      _ => null,
    };
    if (step == null) return null;
    return AppTask(
      id: newId,
      title: title,
      dueDate: dueDate.add(step),
      priority: priority,
      notificationId: newNotificationId,
      createdAt: DateTime.now(),
      isRecurring: true,
      recurrenceRule: recurrenceRule,
      durationMinutes: durationMinutes,
    );
  }

  AppTask copyWith({
    String? title,
    DateTime? dueDate,
    Priority? priority,
    bool? isCompleted,
    bool? isRecurring,
    String? recurrenceRule,
    int? notificationId,
    int? durationMinutes,
    DateTime? completedAt,
    int? rescheduleCount,
  }) =>
      AppTask(
        id: id,
        title: title ?? this.title,
        dueDate: dueDate ?? this.dueDate,
        priority: priority ?? this.priority,
        isCompleted: isCompleted ?? this.isCompleted,
        isRecurring: isRecurring ?? this.isRecurring,
        recurrenceRule: recurrenceRule ?? this.recurrenceRule,
        notificationId: notificationId ?? this.notificationId,
        createdAt: createdAt,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        completedAt: completedAt ?? this.completedAt,
        rescheduleCount: rescheduleCount ?? this.rescheduleCount,
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'dueDate': Timestamp.fromDate(dueDate),
        'priority': priority.name,
        'isCompleted': isCompleted,
        'isRecurring': isRecurring,
        'recurrenceRule': recurrenceRule,
        'notificationId': notificationId,
        'createdAt': Timestamp.fromDate(createdAt),
        'durationMinutes': durationMinutes,
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
        'rescheduleCount': rescheduleCount,
      };

  factory AppTask.fromMap(String id, Map<String, dynamic> m) => AppTask(
        id: id,
        title: (m['title'] ?? '') as String,
        dueDate: (m['dueDate'] as Timestamp).toDate(),
        priority: priorityFromString(m['priority'] as String?),
        isCompleted: (m['isCompleted'] ?? false) as bool,
        isRecurring: (m['isRecurring'] ?? false) as bool,
        recurrenceRule: m['recurrenceRule'] as String?,
        notificationId: (m['notificationId'] ?? 0) as int,
        createdAt: ((m['createdAt'] as Timestamp?) ?? Timestamp.now()).toDate(),
        durationMinutes: (m['durationMinutes'] ?? 60) as int,
        completedAt: (m['completedAt'] as Timestamp?)?.toDate(),
        rescheduleCount: (m['rescheduleCount'] ?? 0) as int,
      );
}
