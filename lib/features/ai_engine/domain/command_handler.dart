import 'dart:convert';

import '../../../core/config.dart';
import '../../../core/format.dart';
import '../../../core/vi_text.dart';
import '../../activity/domain/activity_entry.dart';
import '../../activity/domain/activity_log.dart';
import '../../tasks/domain/app_task.dart';
import '../../tasks/domain/auto_scheduler.dart';
import '../../tasks/domain/reminder_scheduler.dart';
import '../../tasks/domain/task_matcher.dart';
import '../../tasks/domain/task_repository.dart';
import 'ai_command.dart';

/// Hành động đang chờ người dùng xác nhận (vd xóa hàng loạt).
class _PendingConfirm {
  final DateTime at;
  final Future<String> Function() run;

  /// Câu trả lời khi người dùng nói "không".
  final String cancelMsg;
  _PendingConfirm(this.at, this.run,
      {this.cancelMsg = 'Mình đã hủy, chưa xóa gì cả.'});
}

/// Đang chờ người dùng chọn một (hoặc vài) trong các việc được đọc ra.
class _Choice {
  final DateTime at;
  final List<AppTask> candidates;
  final String verb; // xóa | sửa | hoàn thành
  final bool destructive;
  final Future<String> Function(List<AppTask>) run;
  _Choice(this.at, this.candidates, this.verb, this.destructive, this.run);
}

/// Thao tác gần nhất, dùng cho "hoàn tác".
class _Undo {
  final DateTime at;
  final String label;
  final Future<void> Function() revert;
  _Undo(this.at, this.label, this.revert);
}

/// Điều phối luồng ở Hình 2/3: văn bản → Gemini → (Auto-Scheduling) → Firestore
/// → Push Notification → câu phản hồi (TTS). Giữ trạng thái Pending Clarification (mục 4.5),
/// xác nhận xóa hàng loạt và hoàn tác thao tác gần nhất.
class CommandHandler {
  final CommandParser parser;
  final TaskRepository repo;
  final ReminderScheduler reminders;
  final AutoScheduler scheduler;
  final Future<String> Function(String period) performanceReply;
  final DateTime Function() clock;

  /// Nhật ký hoạt động dùng chung (RAM + Firestore). Mặc định tự tạo từ [repo].
  final ActivityLog log;

  CommandHandler({
    required this.parser,
    required this.repo,
    required this.reminders,
    required this.performanceReply,
    this.scheduler = const AutoScheduler(),
    this.clock = DateTime.now,
    ActivityLog? log,
  }) : log = log ?? ActivityLog(repo, clock: clock);

  static const _pendingTtl = Duration(minutes: 2);
  static const _undoTtl = Duration(minutes: 10);
  static const _confirmDeleteFrom = 2; // xóa từ 2 việc trở lên thì hỏi xác nhận

  static const _yes = <String>{
    'có', 'ok', 'oke', 'đồng ý', 'xác nhận', 'chắc chắn', 'được', 'ừ',
    'vâng', 'dạ', 'đúng rồi', 'làm đi', 'xóa đi', 'xoá đi',
    'đúng', 'đúng vậy', 'chính xác', 'phải', 'phải rồi', 'đúng ạ', 'vâng ạ',
    'dạ đúng', 'dạ đúng rồi', 'ừ đúng rồi',
  };
  static const _no = <String>{
    'không', 'sai', 'sai rồi', 'không phải', 'không đúng', 'nhầm', 'nhầm rồi',
    'không phải rồi',
  };
  static const _cancel = <String>{
    'thôi', 'bỏ qua', 'hủy', 'huỷ', 'không cần', 'thôi khỏi', 'dừng lại',
    'thôi bỏ đi',
  };

  String? _pendingValue; // lệnh trước đang chờ làm rõ (tự hết hạn sau 2 phút)
  DateTime? _pendingAt;
  _PendingConfirm? _confirm;
  _Choice? _choice;
  List<String> _alts = const []; // các cách nghe khác của lượt hiện tại
  String? _ctx; // ngữ cảnh làm rõ của lượt trước (nếu có), dùng để kiểm tra đúng việc
  _Undo? _undo;
  int _doubtStreak = 0; // số lần liên tiếp phải hỏi lại vì nghe không hợp lý
  DateTime? _awaitPerfAt; // đang chờ người dùng nói kỳ cho câu hỏi hiệu suất

  // ── Nhật ký thao tác: AI nhớ mình vừa dời/xóa/hoàn thành/tạo những việc nào ──
  // Lưu ở [log] (RAM + Firestore users/{uid}/activity_logs).
  String _raw = ''; // câu của lượt hiện tại
  String? _turnIntent; // intent của lượt hiện tại (để ghi các lượt không đổi dữ liệu)

  static const _kindVerb = <String, String>{
    'move': 'dời',
    'edit': 'sửa',
    'delete': 'xóa',
    'complete': 'hoàn thành',
    'create': 'tạo',
  };

  void _record(String kind, List<ActivityItem> items, DateTime at) =>
      log.record(kind, items: items, at: at, rawText: _raw);

  String _itemText(ActivityItem i, DateTime now, String kind,
      {bool compact = false}) {
    switch (kind) {
      case 'move':
        if (i.to == null) return i.title;
        if (compact || i.from == null) {
          return '${i.title} (${formatDateTimeVi(i.to!, now)})';
        }
        return '${i.title} từ ${formatDateTimeVi(i.from!, now)} '
            'sang ${formatDateTimeVi(i.to!, now)}';
      case 'create':
        return i.to == null
            ? i.title
            : '${i.title} lúc ${formatDateTimeVi(i.to!, now)}';
      case 'delete':
        return i.from == null
            ? i.title
            : '${i.title} (lúc ${formatDateTimeVi(i.from!, now)})';
      default:
        return i.title;
    }
  }

  String _listItems(List<ActivityItem> items, DateTime now, String kind,
      {int max = 8, bool compact = false}) {
    final shown =
        items.take(max).map((i) => _itemText(i, now, kind, compact: compact));
    final more = items.length > max ? ' và ${items.length - max} việc khác' : '';
    return '${shown.join(', ')}$more';
  }

  /// Trả lời "vừa dời / xóa / hoàn thành những việc nào?" từ nhật ký (không đoán).
  String _recall(AiCommand c, DateTime now) {
    final want = c.actionKind;
    final any = want == null || want == 'any' || !_kindVerb.containsKey(want);
    final rec = log.lastMutation(any ? null : want);
    if (rec == null) {
      return any
          ? 'Mình chưa thực hiện thao tác nào gần đây để nhắc lại.'
          : 'Mình chưa ${_kindVerb[want]} việc nào gần đây.';
    }
    final verb = _kindVerb[rec.kind] ?? 'thao tác';
    final n = rec.items.length;
    return 'Lần $verb gần nhất (lúc ${formatDateTimeVi(rec.at, now)}) gồm $n việc: '
        '${_listItems(rec.items, now, rec.kind, max: 10)}.';
  }

  String? get _pending {
    final at = _pendingAt;
    if (_pendingValue != null &&
        at != null &&
        clock().difference(at) > _pendingTtl) {
      _pendingValue = null;
      _pendingAt = null;
    }
    return _pendingValue;
  }

  set _pending(String? v) {
    _pendingValue = v;
    _pendingAt = v == null ? null : clock();
  }

  bool get awaitingClarification => _pending != null;

  /// Đang chờ một câu trả lời ngắn: "có/không" hoặc chọn việc ("cái thứ hai").
  bool get awaitingConfirmation {
    final c = _confirm;
    if (c != null && clock().difference(c.at) > _pendingTtl) _confirm = null;
    final ch = _choice;
    if (ch != null && clock().difference(ch.at) > _pendingTtl) _choice = null;
    return _confirm != null || _choice != null;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _isUndo(String n) =>
      n.contains('hoàn tác') ||
      n.contains('khôi phục') ||
      n.contains('phục hồi') ||
      n == 'undo';

  /// [alternatives]: các cách nghe khác của máy nhận dạng giọng nói (nếu có),
  /// được chuyển cho bộ phân tích để chọn cách hiểu đúng ngữ cảnh.
  Future<String> handle(String text,
      {List<String> alternatives = const []}) async {
    _raw = text.trim();
    _alts = alternatives;
    _turnIntent = null;
    final before = log.version;
    final reply = await _handleCore(text, alternatives: alternatives);
    if (log.version == before) {
      // Lượt này không đổi dữ liệu (hỏi lịch, hiệu suất, trò chuyện, làm rõ,
      // xác nhận, hủy...) → vẫn ghi lại thành một lần tương tác.
      log.record('interaction', intent: _turnIntent, rawText: _raw, summary: reply);
    }
    return reply;
  }

  Future<String> _handleCore(String text,
      {List<String> alternatives = const []}) async {
    final raw = text.trim();
    if (raw.isEmpty) return 'Mình chưa nghe rõ, bạn nói lại nhé.';
    final now = clock();
    final n = _norm(raw);

    // 1) Đang chờ xác nhận (xóa hàng loạt).
    final conf = _confirm;
    if (conf != null) {
      _confirm = null;
      if (now.difference(conf.at) <= _pendingTtl) {
        if (_yes.contains(n)) {
          _turnIntent = 'confirmYes';
          return conf.run();
        }
        if (_no.contains(n) || _cancel.contains(n)) {
          _turnIntent = 'confirmNo';
          _pending = null;
          return conf.cancelMsg;
        }
        // Câu khác → bỏ xác nhận, xử lý như lệnh mới.
      }
    }
    // 1b) Đang chờ chọn việc ("cái thứ hai", "họp dự án", "tất cả", "thôi").
    final ch = _choice;
    if (ch != null) {
      _choice = null;
      if (now.difference(ch.at) <= _pendingTtl) {
        if (_cancel.contains(n) || _no.contains(n)) {
          _turnIntent = 'cancelChoice';
          _pending = null;
          return 'Mình đã bỏ qua, chưa ${ch.verb} việc nào cả.';
        }
        final picked = _pickFromChoice(n, raw, alternatives, ch.candidates);
        if (picked != null) {
          _turnIntent = 'choice';
          return _confirmOrRun(picked, now, ch.verb, ch.destructive, ch.run,
              sure: true);
        }
        // Câu khác → bỏ lựa chọn, xử lý như lệnh mới.
      }
    }
    // 2) Hoàn tác thao tác gần nhất.
    if (_isUndo(n)) {
      _turnIntent = 'undo';
      return _undoLast(now);
    }
    // 3) Bỏ dở câu hỏi làm rõ.
    if (_pending != null && _cancel.contains(n)) {
      _turnIntent = 'cancelClarify';
      _pending = null;
      return 'Mình đã bỏ qua yêu cầu trước nhé.';
    }

    // 4a) Đang chờ người dùng nói kỳ cho câu hỏi hiệu suất ("tuần này", "tháng"...).
    final awaitAt = _awaitPerfAt;
    if (awaitAt != null) {
      _awaitPerfAt = null;
      if (now.difference(awaitAt) <= _pendingTtl) {
        if (_cancel.contains(n) || _no.contains(n)) {
          _turnIntent = 'cancelClarify';
          _pending = null;
          return 'Mình đã bỏ qua yêu cầu xem hiệu suất nhé.';
        }
        final ans = _pickPerf(raw, alternatives, matchPeriodAnswer);
        if (ans != null && ans.issue != PerfIssue.missing) {
          _turnIntent = Intent.askPerformance.name;
          return _handlePerf(ans, raw, now);
        }
        // Câu khác → bỏ chờ kỳ, xử lý như lệnh mới.
      }
    }

    // 4b) Câu hỏi hiệu suất: nhận bằng luật cục bộ.
    //  - Nói đúng kỳ (hôm nay/tuần này/tháng này/năm nay) → làm luôn.
    //  - Nghe gần giống ("thắng", "thấp"...) → hỏi lại trước khi làm.
    //  - KHÔNG nghe thấy kỳ, hoặc kỳ app không hỗ trợ (tuần trước, tháng 9...) → hỏi lại,
    //    tuyệt đối không tự đoán kỳ.
    final perf = _pickPerf(raw, alternatives, matchPerformance);
    if (perf != null) {
      _turnIntent = Intent.askPerformance.name;
      await repo.logVoice(rawText: raw, intent: Intent.askPerformance.name);
      return _handlePerf(perf, raw, now);
    }

    _ctx = _pending; // câu làm rõ trước đó (vd "sửa lịch họp") cũng được tính là đã nói tên việc
    final tasks = await repo.getAll();
    final cmd = await parser.parse(
      text: raw,
      tasks: tasks,
      now: now,
      pendingContext: _pending,
      recentActions: log.recentJson(),
      alternatives: alternatives,
    );
    await repo.logVoice(rawText: raw, intent: cmd.intent.name);
    _turnIntent = cmd.intent.name;

    if (cmd.intent == Intent.needClarification) {
      _pending = _pending == null ? raw : '$_pending | $raw';
      return vietnameseOr(cmd.question, 'Bạn có thể nói rõ hơn được không?');
    }

    // 5) Nghe không hợp lý (nghi sai âm): hỏi lại trước khi thực hiện.
    if (cmd.hasDoubt) {
      _turnIntent = 'doubt';
      if (_doubtStreak >= 2) {
        _doubtStreak = 0;
        _pending = null;
        return 'Mình vẫn nghe chưa rõ. Bạn thử nói chậm hơn, hoặc gõ lệnh vào ô chat nhé.';
      }
      _doubtStreak++;
      final fixed = cmd.doubtCorrected!;
      _pending = 'Người dùng nói "$raw" (bản chép lời từ giọng nói, có thể sai). '
          'Mình nghi ý bạn là "$fixed" và đã hỏi lại.';
      _confirm = _PendingConfirm(
        now,
        () async {
          _doubtStreak = 0;
          _pending = null;
          _raw = raw; // kiểm tra "đúng việc" theo câu gốc, không phải chữ "đúng rồi"
          _alts = alternatives;
          return _execute(cmd, await repo.getAll(), clock(), raw);
        },
        cancelMsg: 'Vậy bạn nói lại lệnh giúp mình nhé.',
      );
      return 'Mình nghe là "$raw". Có phải ý bạn là "$fixed" không?';
    }
    _doubtStreak = 0;
    _pending = null;
    return _execute(cmd, tasks, now, raw);
  }

  Future<String> _execute(
      AiCommand cmd, List<AppTask> tasks, DateTime now, String rawText) async {
    switch (cmd.intent) {
      case Intent.createTask:
        return _create(cmd, tasks, now);
      case Intent.updateTask:
        return _update(cmd, tasks, now);
      case Intent.deleteTask:
        return _delete(cmd, tasks);
      case Intent.completeTask:
        return _complete(cmd, tasks, now);
      case Intent.queryTasks:
        return _query(cmd, tasks, now);
      case Intent.askPerformance:
        // Chỉ làm khi câu nói THẬT SỰ có kỳ (đừng tin Gemini tự đoán / mặc định "tuần này").
        final said = matchPeriodAnswer(rawText);
        // Nghe đúng chuẩn thì tin câu nói; nghe gần giống thì dùng kỳ Gemini đã sửa lại.
        final p = (said != null && said.exact) ? said.period : cmd.period;
        if (said == null || said.issue == PerfIssue.missing) {
          return _handlePerf(const PerfMatch.missing(), rawText, now);
        }
        if (said.issue == PerfIssue.unsupported) {
          return _handlePerf(said, rawText, now);
        }
        if (p == null || !perfPeriodLabel.containsKey(p)) {
          return _handlePerf(const PerfMatch.missing(), rawText, now);
        }
        final fb = await performanceReply(p);
        _pending = 'Trợ lý vừa nhận xét hiệu suất và hỏi lại người dùng: "$fb"';
        return fb;
      case Intent.recallAction:
        return _recall(cmd, now);
      case Intent.chitchat:
        return _chitchat(cmd);
      default:
        return 'Mình chưa hiểu yêu cầu này. Bạn thử nói như "sáng mai 9h họp dự án" nhé.';
    }
  }

  static const _askPeriod =
      'Bạn muốn xem hiệu suất kỳ nào: hôm nay, tuần này, tháng này hay năm nay?';

  /// Gộp kết quả nhận diện từ câu chính và các cách nghe khác của máy nhận dạng.
  /// Chỉ CÂU CHÍNH được coi là "nghe đúng". Kỳ chỉ xuất hiện ở cách nghe khác thì
  /// phải hỏi lại người dùng (exact = false), không tự làm.
  PerfMatch? _pickPerf(
      String raw, List<String> alts, PerfMatch? Function(String) match) {
    final main = match(raw);
    if (main != null && main.issue != PerfIssue.missing) return main;
    final cands = alts.map(match).whereType<PerfMatch>().toList();
    final ok = cands.where((p) => p.issue == PerfIssue.none).firstOrNull;
    if (ok != null) return PerfMatch(ok.period, false);
    return main ?? cands.firstOrNull;
  }

  /// Xử lý một câu hỏi hiệu suất theo 3 trường hợp: thiếu kỳ / kỳ không hỗ trợ / có kỳ.
  Future<String> _handlePerf(PerfMatch perf, String raw, DateTime now) async {
    _doubtStreak = 0;
    if (perf.issue == PerfIssue.missing) {
      _awaitPerfAt = now;
      _pending = 'Người dùng muốn xem hiệu suất nhưng chưa nói kỳ nào '
          '(câu nghe được: "$raw"). Mình đã hỏi lại: hôm nay, tuần này, tháng này hay năm nay.';
      return _askPeriod;
    }
    if (perf.issue == PerfIssue.unsupported) {
      _awaitPerfAt = now;
      _pending = 'Người dùng hỏi hiệu suất với kỳ mình không hỗ trợ (câu nghe được: "$raw"). '
          'Mình đã hỏi lại: hôm nay, tuần này, tháng này hay năm nay.';
      return 'Mình chỉ đánh giá được hiệu suất trọn một kỳ hiện tại: hôm nay, tuần này, '
          'tháng này hoặc năm nay. Bạn muốn xem kỳ nào?';
    }
    final period = perf.period!;
    Future<String> runPerf() async {
      _pending = null;
      final fb = await performanceReply(period);
      _pending = 'Trợ lý vừa nhận xét hiệu suất và hỏi lại người dùng: "$fb"';
      return fb;
    }

    if (perf.exact) return runPerf();
    final label = perfPeriodLabel[period] ?? '';
    _pending = 'Người dùng nói "$raw" (bản chép lời từ giọng nói, có thể sai). '
        'Mình đã hỏi lại có phải muốn xem hiệu suất $label không.';
    _confirm = _PendingConfirm(now, runPerf,
        cancelMsg: 'Vậy bạn nói lại kỳ cần xem giúp mình nhé.');
    return 'Mình nghe là "$raw". Có phải bạn muốn xem hiệu suất $label không?';
  }

  String _chitchat(AiCommand c) {
    // Nếu mô hình lỡ trả lời tiếng Anh thì dùng câu tiếng Việt mặc định.
    return vietnameseOr(c.reply,
        'Chào bạn! Mình là trợ lý công việc, bạn cần mình xếp lịch gì không?');
  }

  Future<String> _undoLast(DateTime now) async {
    final u = _undo;
    _undo = null;
    if (u == null || now.difference(u.at) > _undoTtl) {
      return 'Mình không còn thao tác nào để hoàn tác.';
    }
    await u.revert();
    log.markLastUndone(u.label); // đánh dấu đã hoàn tác + ghi mục 'undo'
    return 'Đã hoàn tác: ${u.label}.';
  }

  Future<String> _create(AiCommand c, List<AppTask> tasks, DateTime now) async {
    final title = c.title;
    if (title == null || title.isEmpty) {
      _pending = 'Tạo việc mới nhưng chưa có tên';
      return 'Bạn muốn tạo công việc gì?';
    }
    if (c.dueDate != null &&
        c.dueDate!.isBefore(now.subtract(const Duration(minutes: 1)))) {
      _pending = 'Tạo "$title" nhưng thời điểm nói đã ở quá khứ';
      return 'Thời điểm đó đã qua rồi. Bạn muốn xếp "$title" vào lúc nào?';
    }
    // Nghe lặp / nói hai lần → đừng tạo trùng: đã có việc cùng tên trong cùng ngày thì hỏi lại.
    final day = c.dueDate ?? now;
    final dup = tasks
        .where((x) =>
            !x.isCompleted &&
            TaskMatcher.fold(x.title.trim()) == TaskMatcher.fold(title.trim()) &&
            isSameDay(x.dueDate, day))
        .firstOrNull;
    if (dup != null) {
      _confirm = _PendingConfirm(
        clock(),
        () async => _createCore(c, title, await repo.getAll(), clock()),
        cancelMsg: 'Mình không tạo thêm nhé.',
      );
      return 'Bạn đã có ${_one(dup, now)} rồi. Có tạo thêm một việc nữa không?';
    }
    return _createCore(c, title, tasks, now);
  }

  Future<String> _createCore(
      AiCommand c, String title, List<AppTask> tasks, DateTime now) async {
    final dur = c.durationMinutes ?? AppConfig.defaultDurationMinutes;
    final slot = scheduler.findSlot(
      requested: c.dueDate,
      durationMinutes: dur,
      existing: tasks,
      now: now,
    );
    final saved = await repo.add(AppTask(
      id: '',
      title: title,
      dueDate: slot.start,
      priority: c.priority ?? Priority.medium,
      notificationId: newNotificationId(),
      createdAt: now,
      durationMinutes: dur,
      isRecurring: c.recurrenceRule != null,
      recurrenceRule: c.recurrenceRule,
    ));
    await reminders.scheduleForTask(saved);
    _record('create', [ActivityItem(saved.id, title, to: slot.start)], now);
    _undo = _Undo(now, 'tạo "$title"', () async {
      await reminders.cancelForTask(saved);
      await repo.delete(saved.id);
    });

    final when = formatDateTimeVi(slot.start, now);
    if (slot.adjusted && c.dueDate != null) {
      return 'Khung ${formatTimeVi(c.dueDate!)} đã có việc khác nên mình xếp "$title" '
          'vào lúc $when.';
    }
    return 'Đã xếp lịch $title lúc $when.';
  }

  // ───────── Xác định ĐÚNG việc cần sửa / xóa / hoàn thành ─────────
  //
  // Gemini chọn id việc, nhưng khi nghe cụt / sai tên thì có thể chọn nhầm. Vì vậy
  // mọi thao tác trên việc có sẵn đều đi qua [_withTargets]:
  //  1) Không chọn được việc nào → tự tìm gần đúng theo tên rồi hỏi lại (không đoán).
  //  2) Khớp nhiều việc mà không nói "tất cả" → đọc danh sách, bắt chọn (không làm hàng loạt).
  //  3) Việc được chọn không khớp với điều người dùng NÓI → hỏi "có phải ... không?".
  //  4) XÓA luôn đọc lại tên + giờ để xác nhận trước khi xóa (bật/tắt bằng cờ dưới).

  /// true: mọi lần xóa đều hỏi xác nhận. false: chỉ hỏi khi xóa nhiều việc hoặc chưa chắc đúng việc.
  static const _confirmEveryDelete = true;

  List<AppTask> _targets(AiCommand c, List<AppTask> tasks) {
    final ids = c.targetTaskIds.toSet();
    return tasks.where((t) => ids.contains(t.id)).toList();
  }

  String _one(AppTask t, DateTime now) =>
      '"${t.title}" (lúc ${formatDateTimeVi(t.dueDate, now)})';

  String _many(List<AppTask> l, DateTime now, {int max = 4}) {
    final shown = l.take(max).map((t) => _one(t, now)).join(', ');
    final more = l.length > max ? ' và ${l.length - max} việc khác' : '';
    return '$shown$more';
  }

  String _numbered(List<AppTask> l, DateTime now) => [
        for (var i = 0; i < l.length; i++) '${i + 1}. ${_one(l[i], now)}',
      ].join('; ');

  /// Việc được chọn có khớp với điều người dùng đã NÓI không (câu này, các cách nghe
  /// khác, hoặc câu làm rõ trước đó)? Hoặc là việc vừa tạo/dời mà người dùng gọi "việc đó".
  bool _grounded(AppTask t) {
    final spoken = [_raw, ..._alts, if (_ctx != null) _ctx!];
    if (TaskMatcher.bestScore(spoken, t.title) >= 0.6) return true;
    final last = log.lastMutation();
    if (last != null && last.items.any((i) => i.id == t.id)) {
      final w = _norm(_raw).split(' ');
      if (w.contains('đó') || w.contains('vừa') || w.contains('ấy')) return true;
    }
    return false;
  }

  /// Chạy [run] với bản MỚI NHẤT của các việc (đề phòng dữ liệu đổi trong lúc chờ xác nhận).
  Future<String> _fresh(
      List<AppTask> t, Future<String> Function(List<AppTask>) run) async {
    final ids = t.map((x) => x.id).toSet();
    final cur = (await repo.getAll()).where((x) => ids.contains(x.id)).toList();
    if (cur.isEmpty) return 'Việc này không còn trong danh sách nữa.';
    return run(cur);
  }

  Future<String> _withTargets(
    AiCommand c,
    List<AppTask> tasks,
    DateTime now, {
    required String verb,
    required bool destructive,
    required Future<String> Function(List<AppTask> targets) run,
    bool onlyOpen = false,
  }) async {
    final pool = onlyOpen ? tasks.where((t) => !t.isCompleted).toList() : tasks;
    final t = _targets(c, pool);

    // 1) Không chọn được việc nào (nghe cụt / sai tên): tự tìm gần đúng rồi hỏi lại.
    if (t.isEmpty) {
      final spoken = [_raw, ..._alts, if (_ctx != null) _ctx!];
      final found = TaskMatcher.search(spoken, pool, max: 3);
      if (found.isEmpty) {
        _pending = 'Muốn $verb một việc nhưng chưa rõ việc nào '
            '(câu nghe được: "$_raw")';
        return 'Mình chưa tìm thấy việc nào khớp. Bạn nói rõ tên việc muốn $verb nhé.';
      }
      return _askWhich(found, now, verb, destructive, run,
          intro: 'Mình chưa chắc bạn muốn $verb việc nào.');
    }
    // 2) Khớp nhiều việc mà không nói "tất cả": bắt chọn, không làm hàng loạt.
    if (t.length > 1 && !c.isBatch) {
      return _askWhich(t, now, verb, destructive, run,
          intro: 'Có ${t.length} việc khớp.');
    }
    // 3) Một việc / hàng loạt: người dùng có thật sự nhắc tới việc này không?
    final sure = c.isBatch || (t.length == 1 && _grounded(t.first));
    return _confirmOrRun(t, now, verb, destructive, run, sure: sure);
  }

  Future<String> _askWhich(
    List<AppTask> cand,
    DateTime now,
    String verb,
    bool destructive,
    Future<String> Function(List<AppTask>) run, {
    required String intro,
  }) async {
    final list = cand.take(5).toList();
    if (list.length == 1) {
      return _confirmOrRun(list, now, verb, destructive, run, sure: false);
    }
    _choice = _Choice(clock(), list, verb, destructive, run);
    return '$intro Bạn muốn $verb việc nào: ${_numbered(list, now)}? '
        'Nói số thứ tự, tên việc, hoặc "tất cả" nhé.';
  }

  Future<String> _confirmOrRun(
    List<AppTask> t,
    DateTime now,
    String verb,
    bool destructive,
    Future<String> Function(List<AppTask>) run, {
    required bool sure,
  }) async {
    final needConfirm = destructive
        ? (_confirmEveryDelete || t.length >= _confirmDeleteFrom || !sure)
        : !sure;
    if (!needConfirm) return run(t);
    _confirm = _PendingConfirm(
      clock(),
      () => _fresh(t, run),
      cancelMsg: 'Mình đã hủy, chưa $verb gì cả.',
    );
    if (destructive) {
      return t.length == 1
          ? 'Mình sắp xóa ${_one(t.first, now)}. Bạn xác nhận nhé?'
          : 'Mình sắp xóa ${t.length} việc: ${_many(t, now)}. Bạn xác nhận nhé?';
    }
    return t.length == 1
        ? 'Có phải bạn muốn $verb ${_one(t.first, now)} không?'
        : 'Bạn muốn $verb ${t.length} việc: ${_many(t, now)}. Đúng không?';
  }

  /// Hiểu câu trả lời cho "bạn muốn ... việc nào?": số thứ tự, "đầu/cuối", "tất cả", hoặc tên việc.
  List<AppTask>? _pickFromChoice(
      String n, String raw, List<String> alts, List<AppTask> c) {
    final words = n.split(' ');
    if (n.contains('tất cả') ||
        n.contains('cả hai') ||
        n.contains('cả ba') ||
        n.contains('toàn bộ') ||
        words.contains('hết')) {
      return c;
    }
    const ord = <String, int>{
      'một': 0, '1': 0, 'đầu': 0, 'nhất': 0,
      'hai': 1, '2': 1,
      'ba': 2, '3': 2,
      'bốn': 3, '4': 3,
      'năm': 4, '5': 4,
      'cuối': -1,
    };
    for (final w in words) {
      final i = ord[w];
      if (i == null) continue;
      final idx = i == -1 ? c.length - 1 : i;
      if (idx < c.length) return [c[idx]];
    }
    // Theo tên: chỉ nhận khi MỘT việc nổi trội, nếu không thì thôi (xử lý như lệnh mới).
    final scored = [
      for (final t in c) (t, TaskMatcher.bestScore([raw, ...alts], t.title)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    if (scored.first.$2 >= 0.5 &&
        (scored.length == 1 || scored.first.$2 > scored[1].$2)) {
      return [scored.first.$1];
    }
    return null;
  }

  // ───────── SỬA ─────────

  Future<String> _update(AiCommand c, List<AppTask> tasks, DateTime now) =>
      _withTargets(c, tasks, now,
          verb: 'sửa',
          destructive: false,
          run: (t) => _updateTargets(c, t, now));

  Future<String> _updateTargets(
      AiCommand c, List<AppTask> t, DateTime now) async {
    final nothing = c.dueDate == null &&
        (c.title == null || c.title!.isEmpty) &&
        c.priority == null &&
        c.durationMinutes == null;
    if (nothing) {
      // Nghe cụt: biết việc nào nhưng chưa biết đổi gì → hỏi, không "cập nhật" rỗng.
      if (t.length == 1) {
        _pending = 'Sửa việc "${t.first.title}" nhưng chưa nói đổi gì';
        return 'Bạn muốn sửa "${t.first.title}" thế nào: đổi giờ, đổi tên hay đổi độ ưu tiên?';
      }
      _pending = 'Sửa ${t.length} việc nhưng chưa nói đổi gì';
      return 'Bạn muốn dời ${t.length} việc này sang lúc nào?';
    }
    final all = await repo.getAll();
    if (t.length > 1) return _updateMany(c, t, all, now);

    if (c.dueDate != null &&
        c.dueDate!.isBefore(now.subtract(const Duration(minutes: 1)))) {
      _pending = 'Dời "${t.first.title}" nhưng thời điểm nói đã ở quá khứ';
      return 'Thời điểm đó đã qua rồi. Bạn muốn dời "${t.first.title}" sang lúc nào?';
    }
    final old = t.first;
    var next = old;
    var moved = false;
    if (c.dueDate != null) {
      final slot = scheduler.findSlot(
        requested: c.dueDate,
        durationMinutes: c.durationMinutes ?? old.durationMinutes,
        existing: all,
        now: now,
        ignoreTaskId: old.id,
      );
      next = next.copyWith(
        dueDate: slot.start,
        rescheduleCount: old.rescheduleCount + 1,
      );
      moved = true;
    }
    if (c.title != null && c.title!.isNotEmpty) next = next.copyWith(title: c.title);
    if (c.priority != null) next = next.copyWith(priority: c.priority);
    if (c.durationMinutes != null) {
      next = next.copyWith(durationMinutes: c.durationMinutes);
    }
    await repo.update(next);
    // Đồng bộ AI ↔ Push: hủy đăng ký cũ, tạo đăng ký mới theo mốc cập nhật.
    await reminders.cancelForTask(old);
    await reminders.scheduleForTask(next);
    final updated = next;
    _record(
      moved ? 'move' : 'edit',
      [
        ActivityItem(old.id, next.title,
            from: moved ? old.dueDate : null, to: moved ? next.dueDate : null)
      ],
      now,
    );
    _undo = _Undo(now, 'sửa "${old.title}"', () async {
      await repo.update(old);
      await reminders.cancelForTask(updated);
      await reminders.scheduleForTask(old);
    });
    return moved
        ? 'Đã dời "${next.title}" sang ${formatDateTimeVi(next.dueDate, now)}.'
        : 'Đã cập nhật "${next.title}".';
  }

  /// Dời / đổi ưu tiên hàng loạt: các việc được xếp lần lượt, không chồng nhau.
  Future<String> _updateMany(
      AiCommand c, List<AppTask> targets, List<AppTask> all, DateTime now) async {
    if (c.dueDate == null && c.priority == null && c.durationMinutes == null) {
      _pending = 'Sửa hàng loạt ${targets.length} việc nhưng chưa nói đổi gì';
      return 'Bạn muốn dời ${targets.length} việc này sang lúc nào?';
    }
    if (c.dueDate != null &&
        c.dueDate!.isBefore(now.subtract(const Duration(minutes: 1)))) {
      _pending = 'Dời ${targets.length} việc nhưng thời điểm nói đã ở quá khứ';
      return 'Thời điểm đó đã qua rồi. Bạn muốn dời ${targets.length} việc sang lúc nào?';
    }
    final ids = targets.map((e) => e.id).toSet();
    // Lịch cố định = mọi việc không bị dời; việc vừa dời được thêm dần vào.
    final busy = all.where((x) => !ids.contains(x.id)).toList();
    final ordered = [...targets]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final moved = <(AppTask, AppTask)>[]; // (bản cũ, bản mới)
    for (final old in ordered) {
      var next = old;
      if (c.dueDate != null) {
        final slot = scheduler.findSlot(
          requested: c.dueDate,
          durationMinutes: c.durationMinutes ?? old.durationMinutes,
          existing: busy,
          now: now,
        );
        next = next.copyWith(
          dueDate: slot.start,
          rescheduleCount: old.rescheduleCount + 1,
        );
      }
      if (c.priority != null) next = next.copyWith(priority: c.priority);
      if (c.durationMinutes != null) {
        next = next.copyWith(durationMinutes: c.durationMinutes);
      }
      await repo.update(next);
      await reminders.cancelForTask(old);
      await reminders.scheduleForTask(next);
      busy.add(next);
      moved.add((old, next));
    }
    final movedTime = c.dueDate != null;
    final kind = movedTime ? 'move' : 'edit';
    _record(
      kind,
      [
        for (final (old, next) in moved)
          ActivityItem(old.id, next.title,
              from: movedTime ? old.dueDate : null,
              to: movedTime ? next.dueDate : null),
      ],
      now,
    );
    _undo = _Undo(now, 'sửa ${targets.length} việc', () async {
      for (final (old, next) in moved) {
        await repo.update(old);
        await reminders.cancelForTask(next);
        await reminders.scheduleForTask(old);
      }
    });
    // Đọc rõ từng việc đã dời để người dùng không phải nhớ.
    final list = _listItems(
      [
        for (final (old, next) in moved)
          ActivityItem(old.id, next.title, from: old.dueDate, to: next.dueDate),
      ],
      now,
      kind,
      max: 6,
      compact: true,
    );
    return movedTime
        ? 'Đã dời ${targets.length} việc, xếp lần lượt từ ${formatDateTimeVi(c.dueDate!, now)}: $list.'
        : 'Đã cập nhật ${targets.length} việc: $list.';
  }

  // ───────── XÓA ─────────

  Future<String> _delete(AiCommand c, List<AppTask> tasks) =>
      _withTargets(c, tasks, clock(),
          verb: 'xóa', destructive: true, run: _deleteNow);

  Future<String> _deleteNow(List<AppTask> t) async {
    for (final x in t) {
      await reminders.cancelForTask(x);
      await repo.delete(x.id);
    }
    _record(
      'delete',
      [for (final x in t) ActivityItem(x.id, x.title, from: x.dueDate)],
      clock(),
    );
    _undo = _Undo(
      clock(),
      t.length == 1 ? 'xóa "${t.first.title}"' : 'xóa ${t.length} việc',
      () async {
        for (final x in t) {
          final saved = await repo.add(x);
          try {
            await reminders.scheduleForTask(saved);
          } catch (_) {} // việc quá hạn có thể không đặt nhắc được
        }
      },
    );
    return t.length == 1
        ? 'Đã xóa "${t.first.title}". Nếu nhầm, bạn nói "hoàn tác" nhé.'
        : 'Đã xóa ${t.length} công việc. Nếu nhầm, bạn nói "hoàn tác" nhé.';
  }

  // ───────── HOÀN THÀNH ─────────

  Future<String> _complete(AiCommand c, List<AppTask> tasks, DateTime now) async {
    final asked = _targets(c, tasks);
    if (asked.isNotEmpty && asked.every((x) => x.isCompleted)) {
      return asked.length == 1
          ? '"${asked.first.title}" đã hoàn thành rồi.'
          : 'Những việc này đã hoàn thành rồi.';
    }
    return _withTargets(c, tasks, now,
        verb: 'hoàn thành',
        destructive: false,
        onlyOpen: true,
        run: (t) => _completeNow(t.where((x) => !x.isCompleted).toList(), now));
  }

  Future<String> _completeNow(List<AppTask> t, DateTime now) async {
    if (t.isEmpty) return 'Không có công việc nào cần đánh dấu hoàn thành.';
    final created = <AppTask>[];
    for (final x in t) {
      await reminders.cancelForTask(x);
      await repo.update(x.copyWith(isCompleted: true, completedAt: now));
      final next = x.nextOccurrence('', newNotificationId());
      if (next != null) {
        final saved = await repo.add(next);
        await reminders.scheduleForTask(saved);
        created.add(saved);
      }
    }
    log.record(
      'complete',
      items: [for (final x in t) ActivityItem(x.id, x.title)],
      at: now,
      rawText: _raw,
      summary: created.isEmpty
          ? null
          : 'Tự tạo ${created.length} lần lặp kế tiếp: '
              '${created.map((e) => e.dueDate.toIso8601String().substring(0, 16)).join(', ')}',
    );
    _undo = _Undo(now, 'hoàn thành ${t.length} việc', () async {
      for (final s in created) {
        await reminders.cancelForTask(s);
        await repo.delete(s.id);
      }
      for (final x in t) {
        await repo.update(x); // x là bản chưa hoàn thành
        try {
          await reminders.scheduleForTask(x);
        } catch (_) {}
      }
    });
    return t.length == 1
        ? 'Đã hoàn thành "${t.first.title}". Làm tốt lắm!'
        : 'Đã đánh dấu hoàn thành ${t.length} công việc.';
  }

  /// Trả lời "hôm nay / ngày mai / từ 2h đến 5h chiều... có việc gì".
  /// Có việc trong khoảng đó thì liệt kê, không có thì nói rõ là không có.
  String _query(AiCommand c, List<AppTask> tasks, DateTime now) {
    final filter = c.queryFilter ?? 'all';
    final hasRange = c.rangeStart != null || c.rangeEnd != null;
    final today = DateTime(now.year, now.month, now.day);
    var from = c.rangeStart ?? today;
    var to = c.rangeEnd ?? from.add(const Duration(days: 1));
    if (!to.isAfter(from)) {
      // Mô hình đưa khoảng rỗng/ngược: lấy trọn ngày của mốc được nói.
      if (c.rangeStart == null && c.rangeEnd != null) {
        from = DateTime(to.year, to.month, to.day);
      }
      to = DateTime(from.year, from.month, from.day).add(const Duration(days: 1));
      from = DateTime(from.year, from.month, from.day);
    }
    final label = formatRangeVi(from, to, now); // vd "hôm nay", "ngày mai"
    final singleDay = isSameDay(from, to.subtract(const Duration(minutes: 1)));

    String when(AppTask t) => singleDay || isSameDay(t.dueDate, now)
        ? formatTimeVi(t.dueDate)
        : formatDateTimeVi(t.dueDate, now);
    String describe(List<AppTask> l, {bool withTime = true}) {
      final shown = l
          .take(6)
          .map((t) => withTime ? '${when(t)} ${t.title}' : t.title)
          .join(', ');
      final more = l.length > 6 ? ' và ${l.length - 6} việc khác' : '';
      return '$shown$more';
    }

    bool inWindow(DateTime d) => !d.isBefore(from) && d.isBefore(to);

    // Việc đã hoàn thành: lọc theo thời điểm hoàn thành.
    List<AppTask> doneIn() {
      DateTime at(AppTask t) => t.completedAt ?? t.dueDate;
      return tasks.where((t) => t.isCompleted && inWindow(at(t))).toList()
        ..sort((a, b) => at(a).compareTo(at(b)));
    }

    if (filter == 'done') {
      final done = doneIn();
      if (done.isEmpty) return 'Bạn chưa hoàn thành việc nào $label.';
      return 'Bạn đã hoàn thành ${done.length} việc $label: ${describe(done, withTime: false)}.';
    }

    // Hỏi "quá hạn" mà không nêu khoảng thời gian → xét mọi việc quá hạn.
    final noRange = filter == 'overdue' && !hasRange;
    final inRange = tasks
        .where((t) => !t.isCompleted && (noRange || inWindow(t.dueDate)))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final overdue = inRange.where((t) => t.isOverdue(now)).toList();
    final upcoming = inRange.where((t) => !t.isOverdue(now)).toList();
    final where = noRange ? '' : ' $label';

    if (filter == 'overdue') {
      if (overdue.isEmpty) return 'Bạn không có việc nào quá hạn$where.';
      return 'Bạn có ${overdue.length} việc quá hạn$where: ${describe(overdue)}.';
    }
    if (filter == 'upcoming') {
      if (upcoming.isEmpty) return 'Bạn không có việc nào sắp tới hạn $label.';
      return 'Bạn có ${upcoming.length} việc sắp tới hạn $label: ${describe(upcoming)}.';
    }

    // filter == 'all'
    if (inRange.isEmpty) {
      final done = doneIn();
      if (done.isEmpty) return 'Bạn không có công việc nào $label.';
      // Có việc nhưng đều đã xong: nói rõ để không gây hiểu nhầm.
      return 'Bạn không còn việc nào cần làm $label. '
          'Bạn đã hoàn thành ${done.length} việc: ${describe(done, withTime: false)}.';
    }
    final sb = StringBuffer(
        'Bạn có ${inRange.length} việc $label: ${describe(inRange)}.');
    if (overdue.isNotEmpty && upcoming.isNotEmpty) {
      sb.write(' Trong đó ${overdue.length} việc đã quá hạn.');
    } else if (overdue.isNotEmpty) {
      sb.write(' Tất cả đều đã quá hạn.');
    }
    return sb.toString();
  }
}