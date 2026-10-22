import 'package:flutter/foundation.dart';

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
  AssistantProvider(this.handler, this.voice) {
    _messages.add(const ChatMessage(
      'Xin chào! Nhấn micro và nói, ví dụ: "Sáng mai 9h họp dự án FPT".',
      fromUser: false,
    ));
  }

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  AssistantState _state = AssistantState.idle;
  AssistantState get state => _state;

  String _partial = '';
  String get partial => _partial;

  void _set(AssistantState s) {
    _state = s;
    notifyListeners();
  }
  int _autoFollowUps = 0;
  static const _maxAutoFollowUps = 3;

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
    if (text.trim().isEmpty) {
      _set(AssistantState.idle);
      return;
    }
    await _process(text);
  }

  /// Dùng chung cho giọng nói và ô nhập văn bản dự phòng.
  Future<void> send(String text, {bool speak = true}) {
    _autoFollowUps = 0;
    return _process(text, speak: speak);
  }

  Future<void> _process(String text, {bool speak = true}) async {
    _messages.add(ChatMessage(text, fromUser: true));
    _set(AssistantState.thinking);
    String reply;
    try {
      reply = await handler.handle(text);
    } catch (e) {
      debugPrint('handler error: $e');
      reply = 'Xin lỗi, mình gặp lỗi khi xử lý. Bạn thử nói lại nhé.';
    }
    _messages.add(ChatMessage(reply, fromUser: false));
    _set(speak ? AssistantState.speaking : AssistantState.idle);
    if (!speak) return;
    try {
      await voice.speak(reply);
    } catch (_) {}
    // Người dùng đã ngắt lời (state đã đổi) thì không đụng tới state nữa.
    if (_state != AssistantState.speaking) return;
    _set(AssistantState.idle);
    // Rảnh tay: AI vừa hỏi lại / xin xác nhận → tự nghe câu trả lời.
    final needsAnswer =
        handler.awaitingClarification || handler.awaitingConfirmation;
    if (needsAnswer && _autoFollowUps < _maxAutoFollowUps) {
      _autoFollowUps++;
      await _listenAndSend();
    }
  }}