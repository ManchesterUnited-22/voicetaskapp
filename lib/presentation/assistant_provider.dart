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

  Future<void> toggleMic() async {
    if (_state == AssistantState.listening) {
      await voice.stopListening();
      return;
    }
    if (_state != AssistantState.idle) return;
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
    await send(text);
  }

  /// Dùng chung cho giọng nói và ô nhập văn bản dự phòng.
  Future<void> send(String text, {bool speak = true}) async {
    _messages.add(ChatMessage(text, fromUser: true));
    _set(AssistantState.thinking);
    String reply;
    try {
      reply = await handler.handle(text);
    } catch (e) {
      reply = 'Xin lỗi, mình gặp lỗi khi xử lý: $e';
    }
    _messages.add(ChatMessage(reply, fromUser: false));
    _set(speak ? AssistantState.speaking : AssistantState.idle);
    if (speak) {
      try {
        await voice.speak(reply);
      } catch (_) {}
      _set(AssistantState.idle);
    }
  }
}
