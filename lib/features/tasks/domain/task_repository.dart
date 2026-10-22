import 'app_task.dart';

abstract class TaskRepository {
  Stream<List<AppTask>> watchTasks();
  Future<List<AppTask>> getAll();
  Future<List<AppTask>> getBetween(DateTime from, DateTime to);
  Future<AppTask> add(AppTask task);
  Future<void> update(AppTask task);
  Future<void> delete(String id);

  /// VOICE_LOGS (mục 3.6): nhật ký câu lệnh giọng nói.
  Future<void> logVoice({required String rawText, required String intent});

  /// Ngày đã gửi nhận xét cuối ngày gần nhất (lưu ở users/{uid}.lastDailyCoach).
  Future<DateTime?> getLastDailyCoach();
  Future<void> setLastDailyCoach(DateTime d);

  /// performance_analytics (Bảng 4).
  Future<void> saveAnalytics(Map<String, dynamic> data);
}
