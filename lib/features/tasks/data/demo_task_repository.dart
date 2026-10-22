import 'dart:async';

import '../domain/app_task.dart';
import '../domain/task_repository.dart';

/// CHỈ ĐỂ CHỤP ẢNH BÁO CÁO: kho công việc giả lưu trong bộ nhớ, không ghi Firestore.
/// Bật bằng: flutter run --dart-define=DEMO_DATA=true
/// Sau khi viết báo cáo xong chỉ cần bỏ cờ này (hoặc xóa file này) là về dữ liệu thật.
class DemoTaskRepository implements TaskRepository {
  final _tasks = <AppTask>[];
  final _ctrl = StreamController<List<AppTask>>.broadcast();
  var _seq = 0;

  DemoTaskRepository({DateTime? now}) {
    _seed(now ?? DateTime.now());
  }

  List<AppTask> _sorted() =>
      ([..._tasks]..sort((a, b) => a.dueDate.compareTo(b.dueDate)));

  void _emit() => _ctrl.add(_sorted());

  void _seed(DateTime n) {
    DateTime at(int dayOffset, int hour, [int minute = 0]) =>
        DateTime(n.year, n.month, n.day + dayOffset, hour, minute);

    void put(
      int dayOffset,
      int hour,
      String title, {
      int minute = 0,
      Priority priority = Priority.medium,
      int? doneAfterMin, // null = chưa xong; âm = xong sớm; dương = xong trễ
      int resched = 0,
      int duration = 60,
      String? recurrence,
    }) {
      final due = at(dayOffset, hour, minute);
      final i = _seq++;
      _tasks.add(AppTask(
        id: 'demo$i',
        title: title,
        dueDate: due,
        priority: priority,
        notificationId: 8000 + i * 2,
        createdAt: due.subtract(const Duration(days: 1)),
        isCompleted: doneAfterMin != null,
        completedAt: doneAfterMin == null
            ? null
            : due.add(Duration(minutes: doneAfterMin)),
        isRecurring: recurrence != null,
        recurrenceRule: recurrence,
        durationMinutes: duration,
        rescheduleCount: resched,
      ));
    }

    // ---- Lịch sử 4 ngày trước (phục vụ phân tích hiệu suất) ----
    put(-4, 8, 'Họp nhóm đồ án', doneAfterMin: -10, priority: Priority.high);
    put(-4, 14, 'Viết báo cáo thực tập', doneAfterMin: 90, resched: 1);
    put(-3, 9, 'Học API Gemini', doneAfterMin: -5);
    put(-3, 15, 'Làm bài tập đồ họa', doneAfterMin: 120, resched: 1);
    put(-3, 20, 'Ôn tiếng Anh', doneAfterMin: -15, priority: Priority.low);
    put(-2, 8, 'Họp dự án FPT', doneAfterMin: -20, priority: Priority.high);
    put(-2, 9, 'Sửa lỗi voice chat', doneAfterMin: 0, minute: 30);
    put(-2, 14, 'Nộp báo cáo tuần', resched: 2, priority: Priority.high); // quá hạn
    put(-1, 9, 'Test chức năng nhắc việc', doneAfterMin: -5);
    put(-1, 15, 'Cập nhật slide', doneAfterMin: 75);
    put(-1, 16, 'Trả lời thư khách hàng', minute: 30, priority: Priority.low); // quá hạn

    // ---- Hôm nay ----
    put(0, 8, 'Tập thể dục',
        doneAfterMin: -10, priority: Priority.low, recurrence: 'daily');
    put(0, 9, 'Họp dự án FPT', doneAfterMin: -5, priority: Priority.high);
    put(0, 11, 'Gửi thư cho thầy hướng dẫn',
        minute: 30, priority: Priority.high, duration: 30);
    put(0, 14, 'Họp nhóm đồ án', duration: 90);
    put(0, 16, 'Làm slide báo cáo', minute: 30, priority: Priority.high);
    put(0, 20, 'Ôn tiếng Anh', priority: Priority.low, recurrence: 'daily');

    // ---- Những ngày tới ----
    put(1, 8, 'Họp dự án FPT', minute: 30, priority: Priority.high);
    put(1, 14, 'Nộp báo cáo thực tập', priority: Priority.high);
    put(1, 19, 'Tập thể dục',
        priority: Priority.low, recurrence: 'daily', duration: 45);
    put(2, 9, 'Khám sức khỏe định kỳ', duration: 120);
    put(2, 15, 'Học API Gemini');
    put(3, 10, 'Mua quà sinh nhật bạn', priority: Priority.low);
    put(5, 8, 'Họp tổng kết đồ án', priority: Priority.high, duration: 120);
  }

  @override
  Stream<List<AppTask>> watchTasks() {
    late StreamController<List<AppTask>> c;
    StreamSubscription<List<AppTask>>? sub;
    c = StreamController<List<AppTask>>(
      onListen: () {
        c.add(_sorted());
        sub = _ctrl.stream.listen(c.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  @override
  Future<List<AppTask>> getAll() async => _sorted();

  /// Trả về toàn bộ dữ liệu mẫu cho mọi kỳ (ngày/tuần/tháng/năm) để ảnh báo cáo luôn có số liệu.
  @override
    @override
  Future<List<AppTask>> getBetween(DateTime from, DateTime to) async => _sorted()
      .where((t) => !t.dueDate.isBefore(from) && t.dueDate.isBefore(to))
      .toList();

  @override
  Future<AppTask> add(AppTask task) async {
    final saved = AppTask(
      id: 'demo${_seq++}',
      title: task.title,
      dueDate: task.dueDate,
      priority: task.priority,
      notificationId: task.notificationId,
      createdAt: task.createdAt,
      isCompleted: task.isCompleted,
      isRecurring: task.isRecurring,
      recurrenceRule: task.recurrenceRule,
      durationMinutes: task.durationMinutes,
      completedAt: task.completedAt,
      rescheduleCount: task.rescheduleCount,
    );
    _tasks.add(saved);
    _emit();
    return saved;
  }

  @override
  Future<void> update(AppTask task) async {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) _tasks[i] = task;
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    _emit();
  }

  @override
  Future<void> logVoice({required String rawText, required String intent}) async {}

  /// Trả về "bây giờ" để không bật thông báo nhận xét cuối ngày khi đang chụp ảnh.
  @override
  Future<DateTime?> getLastDailyCoach() async => DateTime.now();

  @override
  Future<void> setLastDailyCoach(DateTime d) async {}

  @override
  Future<void> saveAnalytics(Map<String, dynamic> data) async {}
}