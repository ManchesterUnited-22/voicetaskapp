import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/config.dart';

/// Speech-to-Text (nghe lệnh) + Text-to-Speech (phản hồi) tiếng Việt.
class VoiceService {
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  bool _ready = false;
  Completer<String>? _activeListening;
  Timer? _finishTimer;
  String _lastRecognized = '';

  void _completeAfter(Duration delay) {
    final active = _activeListening;
    if (active == null || active.isCompleted) return;
    _finishTimer?.cancel();
    _finishTimer = Timer(delay, () {
      if (identical(active, _activeListening) && !active.isCompleted) {
        active.complete(_lastRecognized);
      }
    });
  }

  Future<bool> init() async {
    if (_ready) return true;
    _ready = await _stt.initialize(
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
          // Android can emit the status before delivering its final result.
          _completeAfter(const Duration(milliseconds: 1200));
        }
      },
      onError: (_) {
        _completeAfter(const Duration(milliseconds: 300));
      },
    );
    await _tts.setLanguage('vi-VN');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    return _ready;
  }

  bool get isListening => _stt.isListening;

  /// Nghe một câu lệnh; trả về văn bản cuối cùng (rỗng nếu không nghe được).
  /// [onPartial] nhận văn bản tạm thời để hiển thị trực tiếp.
  Future<String> listenOnce({void Function(String)? onPartial}) async {
    if (!await init()) return '';
    await _tts.stop();
    if (_stt.isListening) await _stt.stop();
    final done = Completer<String>();
    _activeListening = done;
    _finishTimer?.cancel();
    _lastRecognized = '';
    var last = '';
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: AppConfig.locale,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenMode: ListenMode.dictation,
        cancelOnError: false,
      ),
      onResult: (r) {
        _finishTimer?.cancel();
        final recognized = r.recognizedWords.trim();
        if (recognized.isNotEmpty) last = recognized;
        _lastRecognized = last;
        onPartial?.call(last);
        if (r.finalResult && !done.isCompleted) done.complete(last);
      },
    );
    final result = await done.future.timeout(
      const Duration(seconds: 35),
      onTimeout: () => last,
    );
    _finishTimer?.cancel();
    _activeListening = null;
    return result;
  }

  Future<void> stopListening() async {
    await _stt.stop();
    // Give the platform time to deliver the final recognition result.
    _completeAfter(const Duration(milliseconds: 1200));
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(text.trim());
  }

  Future<void> stopSpeaking() => _tts.stop();
}
