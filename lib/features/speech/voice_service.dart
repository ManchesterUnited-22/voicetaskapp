import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/config.dart';

/// Lý do không nghe được, để app báo lại cho người dùng bằng tiếng Việt.
enum VoiceIssue { micDenied, unavailable, noSpeech, network, language, other }

extension VoiceIssueText on VoiceIssue {
  String get message => switch (this) {
        VoiceIssue.micDenied =>
          'Mình chưa có quyền dùng micro. Bạn bật quyền micro cho ứng dụng trong phần Cài đặt nhé.',
        VoiceIssue.unavailable =>
          'Máy bạn chưa có dịch vụ nhận diện giọng nói. Bạn kiểm tra dịch vụ giọng nói của Google trên máy nhé.',
        VoiceIssue.noSpeech =>
          'Mình không nghe thấy gì. Bạn chạm micro rồi nói lại nhé.',
        VoiceIssue.network =>
          'Nhận diện giọng nói cần có mạng. Bạn kiểm tra kết nối rồi thử lại nhé.',
        VoiceIssue.language =>
          'Máy chưa hỗ trợ nhận diện tiếng Việt. Bạn tải gói giọng nói tiếng Việt trong Cài đặt nhé.',
        VoiceIssue.other => 'Mình nghe chưa được, bạn thử lại nhé.',
      };
}

/// Speech-to-Text (nghe lệnh) + Text-to-Speech (phản hồi) tiếng Việt.
class VoiceService {
  final _stt = SpeechToText();
  final _tts = FlutterTts();

  // ───────────────────────────── STT ─────────────────────────────

  bool _ready = false;
  Future<bool>? _initFuture;
  String _localeId = AppConfig.locale;

  VoiceIssue? _issue;

  /// Lý do của lần nghe gần nhất không ra chữ (null = người dùng tự dừng).
  VoiceIssue? get lastIssue => _issue;

  bool get isListening => _stt.isListening;

  // Im bao lâu thì chốt câu. Câu còn dang dở (đang kết ở "và", "lúc", "vào"...,
  // hoặc đang đọc dở số) thì chờ lâu hơn để người dùng kịp nghĩ và nói tiếp.
  static const _endSilence = Duration(milliseconds: 3500);
  static const _endSilenceIncomplete = Duration(milliseconds: 6000);
  static const _noSpeechLimit = Duration(seconds: 10); // không nói gì thì dừng
  static const _maxTotal = Duration(seconds: 60);
  static const _restartDelay = Duration(milliseconds: 150); // càng ngắn càng ít mất chữ
  static const _finalWait = Duration(milliseconds: 1200); // chờ kết quả cuối sau stop()

  // Từ thường nằm ở cuối câu nói dở → chắc chắn người dùng còn nói tiếp.
  static const _danglingWords = <String>{
    'và', 'rồi', 'thì', 'là', 'vào', 'lúc', 'ở', 'tại', 'cho', 'với', 'để',
    'nhưng', 'hoặc', 'hay', 'của', 'trước', 'sau', 'khoảng', 'đến', 'từ',
    'tới', 'về', 'trong', 'ngày', 'tháng', 'tuần', 'nhắc', 'mà', 'nếu', 'khi',
  };
  static const _busyRestartDelay = Duration(milliseconds: 700);
  static const _maxHardErrors = 3;

  Completer<String>? _session;
  Timer? _silenceTimer;
  Timer? _noSpeechTimer;
  Timer? _restartTimer;
  Timer? _finishTimer;
  final _committed = <String>[]; // các đoạn đã chốt
  String _currentPartial = ''; // đoạn đang nói
  bool _stopRequested = false;
  bool _starting = false; // chặn gọi listen() hai lần
  int _hardErrors = 0;
  void Function(String)? _onPartial;
  DateTime _startedAt = DateTime.now();

  // Độ tin cậy + các cách nghe khác (n-best) của lần nghe gần nhất.
  final _segConfidences = <double>[]; // độ tin cậy từng đoạn đã chốt (nếu máy báo)
  final _segAlternates = <List<String>>[]; // cách nghe khác của từng đoạn đã chốt
  double? _lastConfidence;
  List<String> _lastAlternatives = const [];

  /// Độ tin cậy thấp nhất giữa các đoạn (0..1). null = máy không báo.
  double? get lastConfidence => _lastConfidence;

  /// Các cách nghe khác của câu vừa nói (chỉ có khi câu gọn trong 1 đoạn).
  List<String> get lastAlternatives => _lastAlternatives;

  String get _fullText =>
      [..._committed, if (_currentPartial.isNotEmpty) _currentPartial]
          .join(' ')
          .trim();

  bool get _expired => DateTime.now().difference(_startedAt) > _maxTotal;

  Future<bool> init() async {
    if (_ready) return true;
    return _initFuture ??= _initStt().whenComplete(() {
      if (!_ready) _initFuture = null; // cho phép thử lại (vd sau khi bật quyền)
    });
  }

  Future<bool> _initStt() async {
    try {
      _ready = await _stt.initialize(onStatus: _onStatus, onError: _onError);
    } catch (e) {
      debugPrint('STT init lỗi: $e');
      _ready = false;
    }
    if (_ready) {
      try {
        // Chọn đúng locale tiếng Việt mà máy hỗ trợ, ưu tiên vi-VN.
        final locales = await _stt.locales();
        final vi = locales
            .where((l) => l.localeId.toLowerCase().startsWith('vi'))
            .toList();
        if (vi.isNotEmpty) {
          _localeId = vi
              .firstWhere(
                (l) => l.localeId.toLowerCase().replaceAll('_', '-') == 'vi-vn',
                orElse: () => vi.first,
              )
              .localeId;
        }
      } catch (_) {}
      unawaited(_ensureTts());
    } else {
      var granted = false;
      try {
        granted = await _stt.hasPermission;
      } catch (_) {}
      _issue = granted ? VoiceIssue.unavailable : VoiceIssue.micDenied;
    }
    return _ready;
  }

  void _cancelTimers() {
    _silenceTimer?.cancel();
    _noSpeechTimer?.cancel();
    _restartTimer?.cancel();
    _finishTimer?.cancel();
  }

  void _onStatus(String status) {
    // Android tự dừng sau mỗi câu: lên lịch nghe tiếp (đã gộp, không bị gọi đôi).
    if (status == 'notListening' || status == 'done') _scheduleRestart();
  }

  void _onError(SpeechRecognitionError e) {
    final msg = e.errorMsg.toLowerCase();
    debugPrint('STT lỗi: $msg (permanent=${e.permanent})');
    if (msg.contains('no_match') || msg.contains('speech_timeout')) {
      _scheduleRestart(); // im lặng / không khớp: nghe tiếp
    } else if (msg.contains('busy') || msg.contains('client')) {
      // Thường do khởi động lại quá nhanh: chờ lâu hơn rồi thử lại vài lần.
      if (++_hardErrors > _maxHardErrors) {
        _fail(VoiceIssue.other);
      } else {
        _scheduleRestart(_busyRestartDelay);
      }
    } else if (msg.contains('permission')) {
      _fail(VoiceIssue.micDenied);
    } else if (msg.contains('language')) {
      _fail(VoiceIssue.language);
    } else if (msg.contains('network') || msg.contains('server')) {
      _fail(VoiceIssue.network);
    } else {
      _fail(VoiceIssue.other);
    }
  }

  /// Gộp mọi yêu cầu "nghe tiếp" thành một lần duy nhất → không bao giờ gọi listen() đôi.
  void _scheduleRestart([Duration delay = _restartDelay]) {
    final s = _session;
    if (s == null || s.isCompleted) return;
    if (_restartTimer?.isActive ?? false) return;
    _restartTimer = Timer(delay, () {
      final s = _session;
      if (s == null || s.isCompleted) return;
      if (_expired) {
        _finish();
        return;
      }
      if (_stopRequested) return; // đang chốt câu, _finishTimer sẽ lo
      if (_stt.isListening || _starting) return;
      _startSegment();
    });
  }

  void _scheduleFinish(Duration delay) {
    _finishTimer?.cancel();
    _finishTimer = Timer(delay, _finish);
  }

  /// Kết thúc phiên nghe. Nếu đã có chữ thì vẫn trả chữ đó, chỉ báo lỗi khi chưa có gì.
  void _fail(VoiceIssue issue) {
    final s = _session;
    if (s == null || s.isCompleted) return;
    if (_fullText.isEmpty) _issue = issue;
    _finish();
  }

  void _finish() {
    _cancelTimers();
    final s = _session;
    if (s == null || s.isCompleted) return;
    s.complete(_fullText);
  }

  /// Thời gian im lặng cần chờ trước khi chốt câu, tùy câu đã trọn ý hay chưa.
  Duration _silenceFor(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return _endSilence;
    if (t.endsWith(',') || t.endsWith('...')) return _endSilenceIncomplete;
    final last = t
        .split(RegExp(r'\s+'))
        .last
        .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    if (_danglingWords.contains(last)) return _endSilenceIncomplete;
    if (RegExp(r'^\d+$').hasMatch(last)) return _endSilenceIncomplete; // "lúc 9" (còn "giờ")
    return _endSilence;
  }

  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    // Có chữ rồi mà im liên tục thì mới chốt câu (dài/ngắn tùy câu đã trọn ý chưa).
    _silenceTimer = Timer(_silenceFor(_fullText), () async {
      if (_fullText.isEmpty) return;
      _stopRequested = true;
      try {
        await _stt.stop();
      } catch (_) {}
      _scheduleFinish(_finalWait); // chờ kết quả cuối về (về sớm thì chốt sớm)
    });
  }

  /// Chạm micro mà không nói gì: dừng sớm và báo, thay vì mở mic tới 60 giây.
  Future<void> _onNoSpeech() async {
    final s = _session;
    if (s == null || s.isCompleted || _fullText.isNotEmpty) return;
    _issue = VoiceIssue.noSpeech;
    _stopRequested = true;
    try {
      await _stt.cancel();
    } catch (_) {}
    _finish();
  }

  void _commit(String text,
      {double? confidence, List<String> alternates = const []}) {
    // Bỏ qua nếu thiết bị báo kết quả cuối hai lần cho cùng một đoạn.
    if (text.isNotEmpty && (_committed.isEmpty || _committed.last != text)) {
      _committed.add(text);
      _segAlternates.add(alternates);
      if (confidence != null) _segConfidences.add(confidence);
    }
    _currentPartial = '';
  }

  void _onResult(SpeechRecognitionResult r) {
    final s = _session;
    if (s == null || s.isCompleted) return; // kết quả muộn của phiên cũ
    final words = r.recognizedWords.trim();
    if (words.isNotEmpty) {
      _hardErrors = 0; // nghe được chữ → máy đang hoạt động bình thường
      _noSpeechTimer?.cancel();
      if (!_stopRequested) _armSilenceTimer(); // đã yêu cầu dừng thì không hẹn lại
      if (!r.finalResult) _currentPartial = words;
    }
    if (r.finalResult) {
      final alts = r.alternates
          .map((a) => a.recognizedWords.trim())
          .where((w) => w.isNotEmpty && w != words)
          .toSet()
          .take(3)
          .toList();
      // Độ tin cậy 0..1; giá trị <= 0 nghĩa là máy không báo.
      final conf = r.alternates.isNotEmpty ? r.alternates.first.confidence : -1.0;
      // Chốt đoạn này, KHÔNG kết thúc phiên: đợi nghe tiếp.
      _commit(
        words.isNotEmpty ? words : _currentPartial,
        confidence: conf > 0 ? conf : null,
        alternates: alts,
      );
    }
    _onPartial?.call(_fullText);
    // Đang chờ chốt câu mà kết quả cuối đã về → chốt ngay, khỏi chờ hết giờ.
    if (_stopRequested && r.finalResult) {
      _scheduleFinish(const Duration(milliseconds: 150));
    }
  }

  Future<void> _startSegment() async {
    if (_starting) return;
    _starting = true;
    // Đoạn trước chưa kịp chốt thì chốt luôn, tránh mất chữ.
    if (_currentPartial.isNotEmpty) _commit(_currentPartial);
    try {
      await _stt.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          localeId: _localeId,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 10), // để timer của mình quyết định, không để máy cắt sớm
          listenMode: ListenMode.dictation,
          cancelOnError: false,
        ),
      );
    } catch (e) {
      debugPrint('STT listen lỗi: $e');
      if (++_hardErrors > _maxHardErrors) {
        _fail(VoiceIssue.other);
      } else {
        _scheduleRestart(_busyRestartDelay);
      }
    } finally {
      _starting = false;
    }
  }

  /// Nghe một câu lệnh; ghép nhiều đoạn, chỉ kết thúc khi người dùng im
  /// ~3,5 giây (6 giây nếu câu còn dang dở), bấm dừng, hoặc không nói gì sau ~9 giây.
  /// Trả về chuỗi rỗng nếu không nghe được; xem [lastIssue] để biết lý do.
  /// Sau khi xong, xem [lastConfidence] và [lastAlternatives].
  Future<String> listenOnce({void Function(String)? onPartial}) async {
    _issue = null;
    if (!await init()) return '';
    try {
      await _tts.stop();
      if (_stt.isListening) await _stt.cancel();
    } catch (_) {}

    _cancelTimers();
    _session = Completer<String>();
    _committed.clear();
    _currentPartial = '';
    _stopRequested = false;
    _starting = false;
    _hardErrors = 0;
    _segConfidences.clear();
    _segAlternates.clear();
    _lastConfidence = null;
    _lastAlternatives = const [];
    _onPartial = onPartial;
    _startedAt = DateTime.now();
    _noSpeechTimer = Timer(_noSpeechLimit, _onNoSpeech);

    await _startSegment();
    final result = await _session!.future.timeout(
      _maxTotal + const Duration(seconds: 5),
      onTimeout: () => _fullText,
    );

    // Chỉ tin độ tin cậy khi MỌI đoạn đều có điểm và không còn chữ chưa chốt.
    final allScored = _committed.isNotEmpty &&
        _currentPartial.isEmpty &&
        _segConfidences.length == _committed.length;
    _lastConfidence =
        allScored ? _segConfidences.reduce((a, b) => a < b ? a : b) : null;
    _lastAlternatives =
        _committed.length == 1 ? _segAlternates.first : const [];

    _cancelTimers();
    _session = null;
    _onPartial = null;
    try {
      if (_stt.isListening) await _stt.cancel(); // dọn nếu hết giờ mà mic còn mở
    } catch (_) {}
    return result;
  }

  Future<void> stopListening() async {
    _stopRequested = true;
    _silenceTimer?.cancel();
    _noSpeechTimer?.cancel();
    try {
      await _stt.stop();
    } catch (_) {}
    // Chờ nền tảng trả nốt kết quả cuối rồi mới chốt.
    _scheduleFinish(_finalWait);
  }

  // ───────────────────────────── TTS ─────────────────────────────

  Future<void>? _ttsInit;
  bool _viVoiceMissing = false;

  /// true nếu máy chưa có giọng đọc tiếng Việt (biết sau khi [warmUpTts] xong).
  bool get viVoiceMissing => _viVoiceMissing;

  /// Khởi tạo TTS sớm (gọi khi dựng app) để lần đọc đầu không bị chậm/sai.
  Future<void> warmUpTts() => _ensureTts();

  /// TTS tự khởi tạo, không phụ thuộc việc đã bấm micro hay chưa
  /// (trước đây bấm chip gợi ý trước sẽ đọc khi TTS chưa được cấu hình).
  Future<void> _ensureTts() => _ttsInit ??= _initTts().catchError((Object e) {
        debugPrint('TTS init lỗi: $e');
        _ttsInit = null; // cho phép thử lại
      });

  Future<void> _initTts() async {
    // Ưu tiên engine Google TTS (có giọng tiếng Việt rõ nhất trên Android).
    try {
      final engines = await _tts.getEngines;
      if (engines is List && engines.contains('com.google.android.tts')) {
        await _tts.setEngine('com.google.android.tts');
      }
    } catch (_) {}

    var langOk = false;
    var hasViVoice = false;
    try {
      langOk = (await _tts.isLanguageAvailable('vi-VN')) == true;
      await _tts.setLanguage('vi-VN');
      final voices = await _tts.getVoices;
      if (voices is List) {
        final viVoices = voices.whereType<Map>().where((v) {
          final loc = '${v['locale']}'.toLowerCase().replaceAll('_', '-');
          return loc.startsWith('vi');
        }).toList();
        if (viVoices.isNotEmpty) {
          hasViVoice = true;
          final v = viVoices.first;
          await _tts.setVoice({
            'name': '${v['name']}',
            'locale': '${v['locale']}',
          });
        }
      }
    } catch (_) {}
    _viVoiceMissing = !langOk && !hasViVoice;
    if (_viVoiceMissing) debugPrint('TTS: chưa có giọng vi-VN.');

    await _tts.setSpeechRate(0.5); // 0.5 = tốc độ tự nhiên trên Android
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  /// Chuẩn hóa văn bản trước khi đọc: bỏ ký tự gây đọc sai, giữ thuần tiếng Việt.
  String _cleanForSpeech(String text) {
    var s = text;
    s = s.replaceAll(RegExp(r'https?://\S+'), '');
    s = s.replaceAll(RegExp(r'[*_#`>~|]'), '');
    s = s.replaceAll(RegExp(r'["“”\x27]'), '');
    s = s.replaceAll(';', ',');
    // "9h" -> "9 giờ", "9h30" -> "9 giờ 30 phút", "14h05" -> "14 giờ 5 phút"
    s = s.replaceAllMapped(RegExp(r'\b(\d{1,2})h(\d{2})?\b'), (m) {
      final min = m.group(2);
      if (min == null) return '${m[1]} giờ';
      final v = int.parse(min);
      return v == 0 ? '${m[1]} giờ' : '${m[1]} giờ $v phút';
    });
    // "12/10" -> "12 tháng 10", "05/10" -> "5 tháng 10" (ngày/tháng)
    s = s.replaceAllMapped(
      RegExp(r'\b(\d{1,2})/(\d{1,2})\b(?!/)'),
      (m) => '${int.parse(m[1]!)} tháng ${int.parse(m[2]!)}',
    );
    s = s.replaceAll('%', ' phần trăm');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }

  Future<void> speak(String text) async {
    final clean = _cleanForSpeech(text);
    if (clean.isEmpty) return;
    try {
      await _ensureTts();
      await _tts.stop();
      await _tts.setLanguage('vi-VN'); // ép lại mỗi lần, tránh engine tự đổi sang tiếng Anh
      await _tts.setVolume(1.0);
      // Phòng engine không báo "đọc xong" làm app kẹt ở trạng thái "đang trả lời".
      final maxWait = Duration(seconds: 6 + clean.length ~/ 6);
      await _tts.speak(clean).timeout(maxWait, onTimeout: () async {
        await _tts.stop();
      });
    } catch (e) {
      debugPrint('TTS lỗi: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Dừng mọi thứ khi thoát phiên đăng nhập / hủy provider.
  Future<void> shutdown() async {
    _cancelTimers();
    final s = _session;
    if (s != null && !s.isCompleted) s.complete('');
    try {
      await _stt.cancel();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }
}