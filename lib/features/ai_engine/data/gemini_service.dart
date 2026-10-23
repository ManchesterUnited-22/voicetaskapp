import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../core/config.dart';
import '../../../core/vi_text.dart';
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
  "intent": "createTask | updateTask | deleteTask | completeTask | queryTasks | askPerformance | recallAction | chitchat | needClarification | unknown",
  "title": string|null,            // tên việc, bỏ từ đệm như "nhắc tôi", "tạo giúp tôi"
  "dueDate": string|null,          // ISO-8601; createTask/updateTask
  "priority": "high|medium|low"|null,
  "durationMinutes": number|null,
  "recurrenceRule": "daily|weekly"|null,
  "targetTaskIds": [string],       // id lấy từ DANH SÁCH CÔNG VIỆC; nhiều id nếu thao tác hàng loạt
  "rangeStart": string|null, "rangeEnd": string|null,   // queryTasks
  "period": "day|week|month|year"|null,                 // askPerformance
  "actionKind": "move|edit|delete|complete|create|any"|null, // recallAction
  "queryFilter": "overdue|upcoming|done|all"|null,       // queryTasks
  "reply": string|null,            // câu trả lời xã giao khi chitchat (tiếng Việt)
  "question": string|null,         // câu hỏi làm rõ khi needClarification (tiếng Việt)
  "isBatch": boolean,
  "doubt": {"corrected": string, "reason": string}|null   // chỉ khi nghi bản chép lời nghe sai âm
}

Quy tắc:
- Luôn hiểu và phản hồi bằng tiếng Việt; không được trả lời bằng tiếng Anh.
- Trường "question" và mọi câu chữ hướng tới người dùng phải là tiếng Việt thuần, ngắn gọn, không chèn từ tiếng Anh.
- Văn bản đầu vào là bản chép lời từ nhận dạng giọng nói, có thể sai đồng âm, sai dấu, sai số.
  Lỗi hay gặp: "hộp"→"họp", "nhấc"→"nhắc", "rời/giời/dồi"→"dời", "sóa/xoa"→"xóa",
  "chính"↔"chín", "bẩy"→"bảy", "hay"↔"hai", "nằm"→"năm", "sao"→"sáu", "tuấn"→"tuần",
  "hoàng thành"→"hoàn thành", "thấp/thắng/thán"→"tháng".
  1) Ưu tiên bản chính. Chỉ sửa lỗi đồng âm khi dựa vào ngữ cảnh và DANH SÁCH CÔNG VIỆC
     chỉ có MỘT cách hiểu hợp lý.
  2) Nếu có "các khả năng khác của máy nhận dạng", chọn phương án khớp nhất với ngữ cảnh / tên việc đang có.
  3) KHÔNG tự đoán khi cách hiểu làm đổi hành động: câu vô nghĩa, giờ/ngày/con số nghe mơ hồ
     (vd "5 giờ" hay "9 giờ"), hoặc việc cần sửa/xóa/hoàn thành không khớp rõ với việc nào
     → intent = "needClarification", "question" nêu rõ điều nghe được,
     vd "Mình nghe là họp lúc 5 giờ, đúng không, hay bạn nói 9 giờ?".
  4) Không bịa thêm thông tin người dùng không nói.
  5) KIỂM TRA TÍNH HỢP LÝ (quan trọng): trước khi chọn intent, tự hỏi "câu này có nghĩa và hợp lý như một
     lệnh quản lý công việc không?". Nếu có từ/cụm là tiếng Việt hợp lệ nhưng VÔ LÝ trong ngữ cảnh lệnh, và có
     từ đồng âm/gần âm làm câu hợp lý hơn rõ rệt (vd "đánh giá hiệu suất thắng" → "hiệu suất tháng này";
     "hộp dự án" → "họp dự án"; "xóa lịch hợp" → "họp"), thì xử lý lệnh theo cách hiểu đã sửa VÀ điền
     "doubt": {"corrected": câu hoàn chỉnh theo cách hiểu đã sửa (tiếng Việt, tự nhiên), "reason": lý do ngắn}.
     Ứng dụng sẽ hỏi lại người dùng trước khi thực hiện.
     - Chỉ điền "doubt" khi thật sự nghi nghe sai. Câu mạch lạc, hợp lý như đã nghe thì để "doubt" = null,
       không điền chỉ vì muốn chắc ăn.
     - Tên việc, tên riêng, số: không "sửa" nếu không có dấu hiệu vô lý.
     - Nếu vô lý mà không đoán được cách sửa → intent = "needClarification", không điền doubt.
- Người dùng nói thiếu độ ưu tiên → "medium". Cụm như "gấp lắm", "làm ngay", "quan trọng", "ưu tiên số 1", "đừng quên" → "high".
- Chào hỏi, cảm ơn, hỏi bạn là ai, trò chuyện xã giao không liên quan quản lý việc → intent = "chitchat",
  "reply" là 1-2 câu tiếng Việt thân thiện, không chèn tiếng Anh, có thể gợi ý một câu lệnh mẫu.
- queryTasks: nói "quá hạn" → queryFilter="overdue"; "sắp tới hạn/sắp đến hạn" → "upcoming";
  hỏi cả hai hoặc không nói rõ → "all". Khoảng giờ lẻ ("từ 2h chiều đến 5h chiều nay") → rangeStart/rangeEnd
  đúng theo giờ nói. Hỏi việc quá hạn mà không nêu khoảng thời gian → để rangeStart/rangeEnd = null.
- Thao tác hàng loạt ("dời/xóa/hoàn thành tất cả...") → isBatch = true và liệt kê MỌI id thỏa điều kiện trong targetTaskIds.
  Dời hàng loạt dùng intent updateTask kèm dueDate. Nếu chỉ nói ngày + buổi mà không nói giờ:
  sáng → 8h, trưa → 12h, chiều → 14h, tối → 19h của ngày đó.
- Nếu chỉ mơ hồ khớp nhiều việc mà người dùng KHÔNG nói "tất cả" → isBatch = false.
- createTask không nói giờ → dueDate = null (hệ thống sẽ tự chọn khung trống).
- updateTask/deleteTask/completeTask: chọn đúng task trong DANH SÁCH; "xóa tất cả việc quá hạn tuần trước" → liệt kê mọi id thỏa điều kiện.
- CHỌN ĐÍCH CHO SỬA/XÓA/HOÀN THÀNH (rất quan trọng, nhầm là mất dữ liệu):
  + targetTaskIds CHỈ gồm việc có tên khớp RÕ với điều người dùng nói. Không chắc, hoặc câu nghe cụt/thiếu tên
    (vd chỉ "xóa", "sửa", "xong", hoặc tên việc nghe không giống việc nào) → targetTaskIds = [] và vẫn giữ intent;
    ứng dụng sẽ tự tìm việc gần giống rồi hỏi lại người dùng. TUYỆT ĐỐI không chọn việc "cho chắc", không đoán.
  + isBatch = true CHỈ khi người dùng nói "tất cả / hết / toàn bộ" hoặc một điều kiện chung
    (quá hạn, hôm nay, tuần trước...). Nói tên một việc → isBatch = false và đúng MỘT id.
  + Tên việc khớp nhiều việc (vd "xóa họp" mà có 2 việc họp) → liệt kê các id khớp, isBatch = false
    (ứng dụng sẽ đọc danh sách cho người dùng chọn).
- Nếu thiếu thực thể bắt buộc (vd "sửa lịch họp" nhưng không nói giờ mới, hoặc có nhiều task khớp mơ hồ) → intent = "needClarification" kèm "question" ngắn gọn bằng tiếng Việt.
- "Hôm nay tôi làm việc thế nào?" → askPerformance với period phù hợp.
  askPerformance: CHỈ điền period khi người dùng NÓI RÕ kỳ (hôm nay / tuần này / tháng này / năm nay).
  Không nói rõ kỳ, hoặc nói kỳ khác (tuần trước, hôm qua, tháng 9, từ ngày A đến ngày B) → period = null,
  TUYỆT ĐỐI không tự đoán hay mặc định "tuần này" (ứng dụng sẽ hỏi lại người dùng).
- Hỏi "hôm nay/ngày mai/tuần này/hôm qua có việc gì" → intent = "queryTasks", queryFilter = "all",
  rangeStart = 00:00 của ngày đầu, rangeEnd = 00:00 của NGÀY SAU ngày cuối (vd "hôm nay" → từ 00:00 hôm nay đến 00:00 ngày mai).
  Hỏi một khoảng giờ cụ thể thì dùng đúng giờ nói. Tuyệt đối không dùng createTask cho câu hỏi.
- Hỏi "đã hoàn thành việc gì" → queryTasks với queryFilter = "done".
- LỊCH SỬ THAO TÁC: nếu có "NHẬT KÝ THAO TÁC GẦN ĐÂY" (mới nhất ở đầu) thì đó là những việc trợ lý VỪA làm.
  + Người dùng hỏi lại về việc vừa làm ("vừa dời những việc nào", "mấy việc đó là gì", "đã xóa việc gì",
    "vừa hoàn thành gì", "nhắc lại giúp mình") → intent = "recallAction", "actionKind" theo loại được hỏi
    (dời → move, sửa → edit, xóa → delete, hoàn thành → complete, tạo → create; không nói rõ → any).
    Không tự trả lời nội dung; ứng dụng sẽ đọc lại từ nhật ký.
  + Người dùng nói "những việc đó / mấy việc vừa rồi / việc vừa dời / việc vừa tạo" trong một lệnh MỚI
    (vd "dời mấy việc đó sang chiều", "đổi việc vừa tạo thành quan trọng") → lấy id trong nhật ký làm targetTaskIds.
    Việc đã bị xóa thì không còn trong DANH SÁCH CÔNG VIỆC, đừng chọn làm đích cho dời/sửa.
- Không hiểu → intent = "unknown".
- Nếu NGỮ CẢNH là nhận xét hiệu suất kèm câu hỏi gợi mở và người dùng đồng ý (có, ok, được, làm đi…),
  hãy đổi lịch các việc liên quan trong DANH SÁCH sang khung giờ hiệu quả được nhắc đến
  (intent = updateTask, isBatch = true, liệt kê targetTaskIds, dueDate theo khung giờ đó).
  Nếu người dùng từ chối hoặc nói chuyện khác thì xử lý như lệnh bình thường.
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
    String? recentActions,
    List<String> alternatives = const [],
  }) async {
    final n = now ?? DateTime.now();
    final user = StringBuffer(_taskContext(tasks, n))..writeln();
    if (recentActions != null && recentActions.isNotEmpty) {
      user.writeln('NHẬT KÝ THAO TÁC GẦN ĐÂY: $recentActions');
    }
    if (pendingContext != null) {
      user.writeln(
          'NGỮ CẢNH (lệnh trước còn thiếu thông tin): $pendingContext');
      user.writeln('Câu trả lời làm rõ của người dùng: "$text"');
      user.writeln('Hãy kết hợp hai câu thành một lệnh hoàn chỉnh.');
    } else {
      user.writeln('Câu lệnh: "$text"');
    }
    if (alternatives.isNotEmpty) {
      user.writeln(
          'Các khả năng khác của máy nhận dạng cho câu người dùng vừa nói: '
          '${alternatives.map((a) => '"$a"').join(' | ')}');
    }
    user.writeln(
        'Nhắc lại: chỉ trả về JSON; mọi chữ hướng tới người dùng (reply, question) phải là tiếng Việt.');
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
Bạn là huấn luyện viên năng suất cá nhân. BẮT BUỘC chỉ dùng tiếng Việt, tuyệt đối không chèn từ tiếng Anh.
Viết câu ngắn, rõ ràng, dễ đọc thành tiếng, thân thiện và tự nhiên như đang trò chuyện.
Dựa trên các chỉ số được cung cấp, viết nhận xét ngắn (tối đa 4 câu): khen điểm tốt, chỉ ra mẫu hành vi đáng chú ý
(vd việc xếp buổi chiều hay trễ, khung giờ hiệu quả nhất), và đề xuất MỘT hành động cụ thể, kết thúc bằng một câu hỏi gợi mở.
Không dùng Markdown, không dùng danh sách. Không bịa số liệu ngoài dữ liệu đã cho.''';
    final user = 'Kỳ phân tích: $periodLabel\n${jsonEncode(m.toJson())}';
    return _generate(system: system, user: user, json: false, temperature: 0.7)
        .then((text) {
      // Lỡ trả lời tiếng Anh thì bỏ, để nơi gọi dùng nhận xét dự phòng tiếng Việt.
      if (!looksVietnamese(text)) {
        throw GeminiException('Phản hồi không phải tiếng Việt');
      }
      return text;
    });
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