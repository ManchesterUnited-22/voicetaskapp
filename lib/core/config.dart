/// Cấu hình ứng dụng. Truyền khóa bằng:
/// flutter run --dart-define=GEMINI_API_KEY=xxxx
class AppConfig {
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  /// Nếu đặt, app gọi Cloud Function này (kèm Firebase ID token) thay vì gọi Gemini trực tiếp,
  /// nên khóa API không nằm trong app. --dart-define=GEMINI_PROXY_URL=https://...
  static const geminiProxyUrl = String.fromEnvironment('GEMINI_PROXY_URL');
  static const geminiModel = 'gemini-2.5-flash';

  /// Giờ làm việc dùng cho thuật toán Auto-Scheduling.
  static const workDayStartHour = 7;
  static const workDayEndHour = 22;

  /// Thời lượng mặc định của một task (phút) khi người dùng không nói.
  static const defaultDurationMinutes = 60;

  /// Nhắc trước hạn (phút) và nhắc quá hạn sau hạn (phút).
  static const reminderLeadMinutes = 15;
  static const overdueDelayMinutes = 1;

  /// Số ngày dữ liệu tối thiểu để AI Coach phân tích (UC-02).
  static const minDaysForCoaching = 3;

  /// Giờ bắt đầu gửi nhận xét cuối ngày.
  static const dailyCoachHour = 20;

  static const locale = 'vi_VN';
}
