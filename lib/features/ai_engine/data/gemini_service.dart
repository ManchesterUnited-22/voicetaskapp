import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../core/config.dart';
import '../../analytics/domain/performance_metrics.dart';
import '../../tasks/domain/app_task.dart';
import '../domain/ai_command.dart';

class GeminiException implements Exception {
  final String message;
  GeminiException(this.message);
  @override
  String toString() => message;
}

/// Gọi Gemini 2.5 Flash qua REST. System Prompt thực hiện 3 nguyên lý (mục 4.1):
/// định hình vai trò, ép JSON schema, quy tắc mặc định/làm rõ.
class GeminiService implements CommandParser {
  final http.Client _client;
  GeminiService({http.Client? client}) : _client = client ?? http.Client();

  static const _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  static String buildParserPrompt(DateTime now) {
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hh = offset.inHours.abs().toString().padLeft(2, '0');
    final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final nowIso =
        '${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(now)}$sign$hh:$mm';
    final weekday = DateFormat('EEEE', 'vi_VN').format(now);
    return '''
Bạn là "Task Parser API" của ứng dụng quản lý công việc bằng giọng nói tiếng Việt.
Chỉ trả về MỘT đối tượng JSON thuần, không Markdown, không lời dẫn, không giải thích.

Thời điểm hiện tại: $nowIso ($weekday). Mọi mốc thời gian phải ở dạng ISO-8601 kèm múi giờ $sign$hh:$mm.
Quy đổi thời gian tương đối ("sáng mai 8h", "chiều thứ 6 tuần sau") dựa trên thời điểm hiện tại.
"Sáng" = 0-11h, "trưa" ≈ 12h, "chiều" = 13-17h, "tối" = 18-23h (vd "3h chiều" = 15:00).

Schema:
{
  "intent": "createTask | updateTask | deleteTask | completeTask | queryTasks | askPerformance | needClarification | unknown",
  "title": string|null,            // tên việc, bỏ từ đệm như "nhắc tôi", "tạo giúp tôi"
  "dueDate": string|null,          // ISO-8601; createTask/updateTask
  "priority": "high|medium|low"|null,
  "durationMinutes": number|null,
  "recurrenceRule": "daily|weekly"|null,
  "targetTaskIds": [string],       // id lấy từ DANH SÁCH CÔNG VIỆC; nhiều id nếu thao tác hàng loạt
  "rangeStart": string|null, "rangeEnd": string|null,   // queryTasks
  "period": "day|week|month|year"|null,                 // askPerformance
  "question": string|null          // câu hỏi làm rõ khi needClarification
}

Quy tắc:
- Luôn hiểu và phản hồi bằng tiếng Việt; không được trả lời bằng tiếng Anh.
- Văn bản đầu vào có thể là bản chép lời từ nhận dạng giọng nói và có lỗi đồng âm.
  Hãy dùng toàn bộ ngữ cảnh câu lệnh để suy luận từ đúng, không máy móc theo một từ
  riêng lẻ (ví dụ "hộp dự án" trong ngữ cảnh lịch làm việc thường là "họp dự án").
  Chỉ sửa cách hiểu khi ngữ cảnh đủ rõ; không tự bịa thêm thông tin người dùng không nói.
- Người dùng nói thiếu độ ưu tiên → "medium". Cụm như "gấp lắm", "làm ngay", "quan trọng", "ưu tiên số 1", "đừng quên" → "high".
- createTask không nói giờ → dueDate = null (hệ thống sẽ tự chọn khung trống).
- updateTask/deleteTask/completeTask: chọn đúng task trong DANH SÁCH; "xóa tất cả việc quá hạn tuần trước" → liệt kê mọi id thỏa điều kiện.
- Nếu thiếu thực thể bắt buộc (vd "sửa lịch họp" nhưng không nói giờ mới, hoặc có nhiều task khớp mơ hồ) → intent = "needClarification" kèm "question" ngắn gọn bằng tiếng Việt.
- "Hôm nay tôi làm việc thế nào?" → askPerformance với period phù hợp.
- Hỏi "hôm nay/ngày mai có việc gì" → queryTasks với rangeStart/rangeEnd bao trọn khoảng đó.
- Không hiểu → intent = "unknown".
''';
  }

  static String _taskContext(List<AppTask> tasks, DateTime now) {
    final fmt = DateFormat("yyyy-MM-dd'T'HH:mm");
    // Chỉ gửi việc chưa xong hoặc trong 30 ngày gần đây (tasks đã sắp theo dueDate tăng dần).
    final cutoff = now.subtract(const Duration(days: 30));
    final relevant = tasks
        .where((t) => !t.isCompleted || t.dueDate.isAfter(cutoff))
        .toList();
    final list = relevant
        .take(150)
        .map((t) => {
              'id': t.id,
              'title': t.title,
              'due': fmt.format(t.dueDate),
              'done': t.isCompleted,
              'overdue': t.isOverdue(now),
            })
        .toList();
    return 'DANH SÁCH CÔNG VIỆC: ${jsonEncode(list)}';
  }

  @override
  Future<AiCommand> parse({
    required String text,
    required List<AppTask> tasks,
    DateTime? now,
    String? pendingContext,
  }) async {
    final n = now ?? DateTime.now();
    final user = StringBuffer(_taskContext(tasks, n))..writeln();
    if (pendingContext != null) {
      user.writeln(
          'NGỮ CẢNH (lệnh trước còn thiếu thông tin): $pendingContext');
      user.writeln('Câu trả lời làm rõ của người dùng: "$text"');
      user.writeln('Hãy kết hợp hai câu thành một lệnh hoàn chỉnh.');
    } else {
      user.writeln('Câu lệnh: "$text"');
    }
    final raw = await _generate(
      system: buildParserPrompt(n),
      user: user.toString(),
      json: true,
      temperature: 0.1,
    );
    return AiCommand.fromJson(decodeJsonLoose(raw));
  }

  /// UC-02: sinh nhận xét/lời khuyên năng suất từ các chỉ số.
  Future<String> coach(PerformanceMetrics m, String periodLabel) {
    const system = '''
Bạn là huấn luyện viên năng suất cá nhân, chỉ nói tiếng Việt, thân thiện và tự nhiên như đang trò chuyện.
Dựa trên các chỉ số được cung cấp, viết nhận xét ngắn (tối đa 4 câu): khen điểm tốt, chỉ ra mẫu hành vi đáng chú ý
(vd việc xếp buổi chiều hay trễ, khung giờ hiệu quả nhất), và đề xuất MỘT hành động cụ thể, kết thúc bằng một câu hỏi gợi mở.
Không dùng Markdown, không dùng danh sách. Không bịa số liệu ngoài dữ liệu đã cho.''';
    final user = 'Kỳ phân tích: $periodLabel\n${jsonEncode(m.toJson())}';
    return _generate(system: system, user: user, json: false, temperature: 0.7);
  }

  Future<String> _generate({
    required String system,
    required String user,
    required bool json,
    required double temperature,
  }) async {
    final useProxy = AppConfig.geminiProxyUrl.isNotEmpty;
    if (!useProxy && AppConfig.geminiApiKey.isEmpty) {
      throw GeminiException(
          'Thiếu GEMINI_API_KEY hoặc GEMINI_PROXY_URL (--dart-define).');
    }
    final uri = useProxy
        ? Uri.parse(AppConfig.geminiProxyUrl)
        : Uri.parse('$_base/${AppConfig.geminiModel}:generateContent');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (useProxy) {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      headers['Authorization'] = 'Bearer $token';
    } else {
      headers['x-goog-api-key'] = AppConfig.geminiApiKey;
    }
    final body = {
      'systemInstruction': {
        'parts': [
          {'text': system}
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': user}
          ]
        }
      ],
      'generationConfig': {
        'temperature': temperature,
        if (json) 'responseMimeType': 'application/json',
      },
    };
    final res = await _client
        .post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw GeminiException('Gemini lỗi ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final parts = (data['candidates'] as List?)?.firstOrNull?['content']
        ?['parts'] as List?;
    final text = parts?.map((p) => p['text'] ?? '').join();
    if (text == null || text.trim().isEmpty) {
      throw GeminiException('Gemini không trả về nội dung');
    }
    return text.trim();
  }

  /// Gỡ rào ```json ... ``` nếu mô hình lỡ thêm vào.
  static Map<String, dynamic> decodeJsonLoose(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r'^```(?:json)?'), '');
      s = s.replaceFirst(RegExp(r'```$'), '').trim();
    }
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw GeminiException('Phản hồi không phải JSON');
    }
    return jsonDecode(s.substring(start, end + 1)) as Map<String, dynamic>;
  }
}
