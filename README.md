# Voice Task App

Ứng dụng quản lý công việc tích hợp AI tương tác giọng nói (theo báo cáo thực tập – Ngô Văn Lập, 24IT137).
Flutter · Firebase Auth/Firestore · Gemini 2.5 Flash · speech_to_text / flutter_tts · flutter_local_notifications.

## Chạy lần đầu
```bash
cd voice_task_app
flutter create . --platforms=android,ios --org com.example   # sinh android/ ios/ (không ghi đè lib/)
flutter pub get
dart pub global activate flutterfire_cli
flutterfire configure                                        # ghi đè lib/firebase_options.dart
flutter test
flutter run --dart-define=GEMINI_API_KEY=<khóa Gemini>
```

## Cấu hình nền tảng
**android/app/src/main/AndroidManifest.xml** (trong `<manifest>`):
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<queries><intent><action android:name="android.speech.RecognitionService"/></intent></queries>
```
Trong `<application>` thêm receiver của flutter_local_notifications (xem README của plugin:
`ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`).
`android/app/build.gradle`: `minSdkVersion 23`, bật `coreLibraryDesugaring` (yêu cầu của flutter_local_notifications).

**ios/Runner/Info.plist**: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`.

## Firestore rules (tối thiểu)
```
match /users/{uid}/{document=**} { allow read, write: if request.auth.uid == uid; }
```
Query `getBetween` dùng 1 trường `dueDate` nên không cần composite index.

## Cấu trúc (Clean Architecture theo feature)
- `features/tasks` – AppTask, **AutoScheduler** (thuần Dart), repository Firestore
- `features/ai_engine` – GeminiService (System Prompt + JSON), **CommandHandler** (điều phối Hình 2/3, Pending Clarification)
- `features/analytics` – PerformanceCalculator + AI Coach (UC-02)
- `features/speech`, `features/notifications`, `features/auth`
- `presentation/` – Provider + 3 màn hình: Trợ lý, Công việc, Coach

## Khác biệt so với báo cáo
- Push dùng **thông báo cục bộ hẹn giờ** (nhắc trước 15 phút + cảnh báo quá hạn sau hạn 1 phút), hủy/đăng ký lại khi dời lịch. FCM chưa dùng vì cần server để gửi khi app bị tắt.
- Thêm field task: `durationMinutes`, `completedAt`, `rescheduleCount` (cần cho phát hiện trùng khoảng giờ và phân tích năng suất).
- Gemini nhận danh sách task kèm id để chọn đúng task khi sửa/xóa/hoàn thành hàng loạt.
- Khóa Gemini nằm trong app qua `--dart-define`: đủ cho demo; bản thật nên gọi qua Cloud Functions.

## Bổ sung
- **Công việc lặp lại**: hoàn thành task `daily`/`weekly` (bằng giọng nói hoặc tick) → tự tạo lần kế tiếp + hẹn thông báo.
- **Giấu khóa Gemini**: `functions/` là proxy (xác thực Firebase ID token). Triển khai xong chạy app với
  `--dart-define=GEMINI_PROXY_URL=https://<region>-<project>.cloudfunctions.net/gemini` (không cần GEMINI_API_KEY).
- `firestore.rules`, `firebase.json`: `firebase deploy --only firestore:rules`.
- `android_config/`: đoạn manifest / Info.plist cần dán sau `flutter create .`.
