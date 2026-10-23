import 'package:flutter/foundation.dart';

import '../core/vi_text.dart';
import '../features/ai_engine/domain/command_handler.dart';
import '../features/speech/voice_service.dart';

class ChatMessage {
  final String text;
  final bool fromUser;
  const ChatMessage(this.text, {required this.fromUser});
}

enum AssistantState { idle, listening, thinking, speaking }

class AssistantProvider extends ChangeNotifier {
  final CommandHandler handler;
  final VoiceService voice;
  bool _disposed = false;
  bool _warnedNoViVoice = false;

  AssistantProvider(this.handler, this.voice) {
    _messages.add(const ChatMessage(
      'Xin chào! Nhấn micro và nói, ví dụ: "Sáng mai 9h họp dự án FPT".',
      fromUser: false,
    ));
    // Khởi tạo TTS sớm; máy thiếu giọng tiếng Việt thì báo một lần.
    voice.warmUpTts().then((_) {
      if (voice.viVoiceMissing) _warnMissingViVoice();
    });
  }

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  AssistantState _state = AssistantState.idle;
  AssistantState get state => _state;

  String _partial = '';
  String get partial => _partial;

  int _autoFollowUps = 0;
  static const _maxAutoFollowUps = 3;

  // Dưới ngưỡng này thì đọc lại câu đã nghe để người dùng xác nhận.
  // Xem log "STT conf=..." để chỉnh cho hợp với máy thật.
  static const _lowConfidence = 0.7;

  static const _yesWords = <String>{
    'đúng', 'đúng rồi', 'đúng vậy', 'chính xác', 'có', 'ừ', 'ok', 'oke',
    'vâng', 'dạ', 'phải', 'phải rồi', 'được',
  };
  static const _noWords = <String>{
    'không', 'sai', 'sai rồi', 'không phải', 'không đúng', 'nhầm', 'nhầm rồi',
  };

  static String _normAnswer(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    voice.shutdown();
    super.dispose();
  }

  void _set(AssistantState s) {
    _state = s;
    notifyListeners();
  }

  void _warnMissingViVoice() {
    if (_disposed || _warnedNoViVoice) return;
    _warnedNoViVoice = true;
    _messages.add(const ChatMessage(
      'Máy bạn chưa cài giọng đọc tiếng Việt nên mình có thể đọc sai hoặc không có tiếng. '
      'Bạn vào Cài đặt > Ngôn ngữ > Chuyển văn bản thành giọng nói để tải giọng tiếng Việt nhé.',
      fromUser: false,
    ));
    notifyListeners();
  }

  Future<void> toggleMic() async {
    if (_state == AssistantState.listening) {
      await voice.stopListening();
      return;
    }
    if (_state == AssistantState.speaking) {
      // Ngắt lời AI: đổi state trước, rồi dừng đọc và nghe ngay.
      _set(AssistantState.idle);
      await voice.stopSpeaking();
    }
    if (_state != AssistantState.idle) return;
    _autoFollowUps = 0;
    await _listenAndSend();
  }

  Future<void> _listenAndSend() async {
    _set(AssistantState.listening);
    String text;
    try {
      text = await voice.listenOnce(onPartial: (p) {
        _partial = p;
        notifyListeners();
      });
    } catch (_) {
      text = '';
    }
    _partial = '';
    if (_disposed) return;
    if (text.trim().isEmpty) {
      final issue = voice.lastIssue;
      if (issue != null) {
        await _say(issue.message); // báo lý do thay vì im lặng
      } else {
        _set(AssistantState.idle); // người dùng tự dừng
      }
      return;
    }

    final conf = voice.lastConfidence;
    final alts = voice.lastAlternatives;
    debugPrint('STT conf=$conf alts=$alts');
    // Máy nghe không chắc → đọc lại cho người dùng xác nhận trước khi làm.
    // (Bỏ qua khi đang chờ "có/không" xác nhận xóa, vì câu đó rất ngắn.)
    if (conf != null && conf < _lowConfidence && !handler.awaitingConfirmation) {
      await _confirmHeard(text, alts);
      return;
    }
    await _process(text, alternatives: alts);
  }

  /// Nghe không chắc: đọc lại câu đã nghe, chờ "đúng/không" rồi mới xử lý.
  Future<void> _confirmHeard(String text, List<String> alternatives) async {
    final ask = 'Mình nghe là: "$text". Đúng không?';
    _messages.add(ChatMessage(ask, fromUser: false));
    _set(AssistantState.speaking);
    try {
      await voice.speak(ask);
    } catch (_) {}
    // Người dùng đã ngắt lời (state đã đổi) thì dừng ở đây.
    if (_disposed || _state != AssistantState.speaking) return;

    _set(AssistantState.listening);
    String ans;
    try {
      ans = await voice.listenOnce(onPartial: (p) {
        _partial = p;
        notifyListeners();
      });
    } catch (_) {
      ans = '';
    }
    final ansAlts = voice.lastAlternatives;
    _partial = '';
    if (_disposed) return;

    final n = _normAnswer(ans);
    if (n.isEmpty) {
      _set(AssistantState.idle); // người dùng im lặng / tự dừng
      return;
    }
    if (_yesWords.contains(n)) {
      await _process(text, alternatives: alternatives);
      return;
    }
    if (_noWords.contains(n)) {
      await _say('Xin lỗi, bạn nói lại giúp mình nhé.');
      if (!_disposed &&
          _state == AssistantState.idle &&
          _autoFollowUps < _maxAutoFollowUps) {
        _autoFollowUps++;
        await _listenAndSend();
      }
      return;
    }
    // Câu khác → coi như người dùng nói lại lệnh.
    await _process(ans, alternatives: ansAlts);
  }

  /// Nói một câu thông báo của hệ thống (không đi qua AI, không tự nghe tiếp).
  Future<void> _say(String msg) async {
    _messages.add(ChatMessage(msg, fromUser: false));
    _set(AssistantState.speaking);
    try {
      await voice.speak(msg);
    } catch (_) {}
    if (_disposed) return;
    if (_state == AssistantState.speaking) _set(AssistantState.idle);
  }

  /// Dùng chung cho giọng nói và các chip gợi ý.
  Future<void> send(String text, {bool speak = true}) {
    _autoFollowUps = 0;
    return _process(text, speak: speak);
  }

  Future<void> _process(String text,
      {bool speak = true, List<String> alternatives = const []}) async {
    _messages.add(ChatMessage(text, fromUser: true));
    _set(AssistantState.thinking);
    String reply;
    try {
      reply = await handler.handle(text, alternatives: alternatives);
    } catch (e) {
      debugPrint('handler error: $e');
      reply = friendlyError(e); // báo đúng nguyên nhân (mất mạng, quá chậm...)
    }
    if (_disposed) return;
    _messages.add(ChatMessage(reply, fromUser: false));
    _set(speak ? AssistantState.speaking : AssistantState.idle);
    if (!speak) return;
    try {
      await voice.speak(reply);
    } catch (_) {}
    // Người dùng đã ngắt lời (state đã đổi) thì không đụng tới state nữa.
    if (_disposed || _state != AssistantState.speaking) return;
    _set(AssistantState.idle);
    // Rảnh tay: AI vừa hỏi lại / xin xác nhận → tự nghe câu trả lời.
    final needsAnswer =
        handler.awaitingClarification || handler.awaitingConfirmation;
    if (needsAnswer && _autoFollowUps < _maxAutoFollowUps) {
      _autoFollowUps++;
      await _listenAndSend();
    }
  }
}