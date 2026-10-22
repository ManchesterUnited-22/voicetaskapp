import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/config.dart';

/// Speech-to-Text (nghe lệnh) + Text-to-Speech (phản hồi) tiếng Việt.
class VoiceService {
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  bool _ready = false;
  String _localeId = AppConfig.locale;

  // Phiên nghe nhiều đoạn: ghép các đoạn lại, chỉ kết thúc khi người dùng im thật sự.
  static const _endSilence = Duration(milliseconds: 2500); // im bao lâu thì chốt
  static const _maxTotal = Duration(seconds: 60);
  Completer<String>? _session;
  Timer? _silenceTimer;
  final _committed = <String>[]; // các đoạn đã chốt
  String _currentPartial = '';   // đoạn đang nói
  bool _stopRequested = false;
  void Function(String)? _onPartial;
  DateTime _startedAt = DateTime.now();

  String get _fullText =>
      [..._committed, if (_currentPartial.isNotEmpty) _currentPartial]
          .join(' ')
          .trim();

  Future<bool> init() async {
    if (_ready) return true;
    _ready = await _stt.initialize(
      onStatus: _onStatus,
      onError: (e) {
        // Lỗi "no match"/"timeout" thường xảy ra khi im lặng: tiếp tục nghe,
        // trừ khi đã hết giờ hoặc người dùng bấm dừng.
        if (e.errorMsg == 'error_no_match' ||
            e.errorMsg == 'error_speech_timeout') {
          _restartOrFinish();
        } else {
          _finish();
        }
      },
    );
    if (_ready) {
      // Chọn đúng locale tiếng Việt mà máy hỗ trợ (vi_VN hoặc vi-VN).
      final locales = await _stt.locales();
      final vi = locales.where((l) => l.localeId.toLowerCase().startsWith('vi'));
      if (vi.isNotEmpty) _localeId = vi.first.localeId;
    }
    await _initTts();
    return _ready;
  }

  Future<void> _initTts() async {
    // Ưu tiên engine Google TTS (có giọng tiếng Việt rõ nhất trên Android).
    try {
      final engines = await _tts.getEngines;
      if (engines is List && engines.contains('com.google.android.tts')) {
        await _tts.setEngine('com.google.android.tts');
      }
    } catch (_) {}

    // Kiểm tra máy đã có giọng tiếng Việt chưa, rồi ghim giọng đó.
    try {
      final ok = await _tts.isLanguageAvailable('vi-VN');
      if (ok == true) {
        await _tts.setLanguage('vi-VN');
      } else {
        await _tts.setLanguage('vi-VN'); // vẫn thử, nhưng báo để người dùng cài giọng
        debugPrint('TTS: chưa có giọng vi-VN. '
            'Cài tại Cài đặt > Ngôn ngữ > Chuyển văn bản thành giọng nói.');
      }
      final voices = await _tts.getVoices;
      if (voices is List) {
        final viVoices = voices.whereType<Map>().where((v) {
          final loc = '${v['locale']}'.toLowerCase().replaceAll('_', '-');
          return loc.startsWith('vi');
        }).toList();
        if (viVoices.isNotEmpty) {
          final v = viVoices.first;
          await _tts.setVoice({
            'name': '${v['name']}',
            'locale': '${v['locale']}',
          });
        }
      }
    } catch (_) {}

    await _tts.setSpeechRate(0.5); // 0.5 = tốc độ tự nhiên trên Android
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);       // mức tối đa của app
    await _tts.awaitSpeakCompletion(true);
  }

  bool get isListening => _stt.isListening;

  void _onStatus(String status) {
    if (status == 'notListening' || status == 'done') {
      // Android tự dừng sau 1 câu: chờ chút cho kết quả cuối về rồi nghe tiếp.
      Future.delayed(const Duration(milliseconds: 400), _restartOrFinish);
    }
  }

  void _restartOrFinish() {
    final s = _session;
    if (s == null || s.isCompleted) return;
    final expired = DateTime.now().difference(_startedAt) > _maxTotal;
    if (_stopRequested || expired) {
      _finish();
      return;
    }
    if (_stt.isListening) return; // đã tự nghe lại rồi
    _startSegment();
  }

  void _finish() {
    final s = _session;
    if (s == null || s.isCompleted) return;
    _silenceTimer?.cancel();
    s.complete(_fullText);
  }

  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    // Có chữ rồi mà im 2,5 giây liên tục thì mới chốt câu.
    _silenceTimer = Timer(_endSilence, () async {
      if (_fullText.isEmpty) return; // chưa nói gì thì cứ chờ
      _stopRequested = true;
      await _stt.stop();
      Future.delayed(const Duration(milliseconds: 500), _finish);
    });
  }

  Future<void> _startSegment() async {
    _currentPartial = '';
    await _stt.listen(
      onResult: (r) {
        final words = r.recognizedWords.trim();
        if (words.isNotEmpty) {
          _currentPartial = words;
          _armSilenceTimer();
        }
        if (r.finalResult) {
          // Chốt đoạn này, KHÔNG kết thúc phiên: đợi nghe tiếp.
          if (_currentPartial.isNotEmpty) {
            _committed.add(_currentPartial);
            _currentPartial = '';
          }
        }
        _onPartial?.call(_fullText);
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: _localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 6),
        listenMode: ListenMode.dictation,
        cancelOnError: false,
      ),
    );
  }

  /// Nghe một câu lệnh; ghép nhiều đoạn, chỉ kết thúc khi người dùng im
  /// ~2,5 giây hoặc bấm dừng. [onPartial] nhận toàn bộ văn bản đang nghe.
  Future<String> listenOnce({void Function(String)? onPartial}) async {
    if (!await init()) return '';
    await _tts.stop();
    if (_stt.isListening) await _stt.cancel();

    _session = Completer<String>();
    _committed.clear();
    _currentPartial = '';
    _stopRequested = false;
    _onPartial = onPartial;
    _startedAt = DateTime.now();
    _silenceTimer?.cancel();

    await _startSegment();
    final result = await _session!.future.timeout(
      _maxTotal + const Duration(seconds: 5),
      onTimeout: () => _fullText,
    );
    _silenceTimer?.cancel();
    _session = null;
    _onPartial = null;
    return result;
  }

  Future<void> stopListening() async {
    _stopRequested = true;
    _silenceTimer?.cancel();
    await _stt.stop();
    // Chờ nền tảng trả nốt kết quả cuối rồi mới chốt.
    Future.delayed(const Duration(milliseconds: 800), _finish);
  }

  /// Chuẩn hóa văn bản trước khi đọc: bỏ ký tự gây đọc sai, giữ thuần tiếng Việt.
  String _cleanForSpeech(String text) {
    var s = text;
    s = s.replaceAll(RegExp(r'https?://\S+'), '');
    s = s.replaceAll(RegExp(r'[*_#`>~|]'), '');
    s = s.replaceAll(RegExp(r'["“”\x27]'), '');
    s = s.replaceAll(';', ',');
    // "9h30" -> "9 giờ 30", "9h" -> "9 giờ"
    s = s.replaceAllMapped(RegExp(r'(\d{1,2})h(\d{2})?\b'), (m) {
      final min = m.group(2);
      return min == null ? '${m[1]} giờ' : '${m[1]} giờ ${int.parse(min)}';
    });
    // "12/10" -> "12 tháng 10" (ngày/tháng)
    s = s.replaceAllMapped(RegExp(r'\b(\d{1,2})/(\d{1,2})\b'),
        (m) => '${m[1]} tháng ${m[2]}');
    s = s.replaceAll('%', ' phần trăm');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }

  Future<void> speak(String text) async {
    final clean = _cleanForSpeech(text);
    if (clean.isEmpty) return;
    await _tts.stop();
    await _tts.setLanguage('vi-VN'); // ép lại mỗi lần, tránh bị engine tự đổi về tiếng Anh
    await _tts.setVolume(1.0);
    await _tts.speak(clean);
  }

  Future<void> stopSpeaking() => _tts.stop();
}