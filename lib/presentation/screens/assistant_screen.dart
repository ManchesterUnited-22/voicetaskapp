import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../assistant_provider.dart';

class _Suggestion {
  final IconData icon;
  final String title;
  final String command;
  final Color color;
  const _Suggestion(this.icon, this.title, this.command, this.color);
}

const _suggestions = [
  _Suggestion(Icons.add_task_rounded, 'Tạo việc mới',
      'Sáng mai 9h họp dự án', Brand.violet),
  _Suggestion(Icons.event_note_rounded, 'Lịch hôm nay',
      'Hôm nay tôi có việc gì?', Brand.blue),
  _Suggestion(Icons.insights_rounded, 'Hiệu suất',
      'Đánh giá hiệu suất tuần này', Brand.orange),
  _Suggestion(Icons.repeat_rounded, 'Việc lặp lại',
      'Nhắc tôi uống thuốc mỗi ngày lúc 8h', Brand.green),
];

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _loop;
  int _lastItems = 0;
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _loop.dispose();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      });

  void _toggleTyping() {
    setState(() => _typing = !_typing);
    if (_typing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    } else {
      _focus.unfocus();
    }
  }

  void _submitText(AssistantProvider a) {
    final t = _input.text.trim();
    if (t.isEmpty || a.state != AssistantState.idle) return;
    _input.clear();
    a.send(t, speak: false); // gõ chữ thì trả lời bằng chữ, không đọc to
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AssistantProvider>();
    final cs = Theme.of(context).colorScheme;
    final msgs = a.messages;
    final idle = a.state == AssistantState.idle;
    final showTyping = a.state == AssistantState.thinking;
    final showPartial =
        a.state == AssistantState.listening && a.partial.isNotEmpty;
    final count = msgs.length + (showTyping || showPartial ? 1 : 0);
    final hero = msgs.length <= 1 && idle;

    if (count != _lastItems) {
      _lastItems = count;
      _scrollDown();
    }

    final (label, color) = switch (a.state) {
      AssistantState.listening => ('Đang nghe bạn nói…', Brand.pink),
      AssistantState.thinking => ('Đang xử lý…', cs.primary),
      AssistantState.speaking => ('Đang trả lời…', const Color(0xFF0891B2)),
      AssistantState.idle => ('Chạm micro để nói', cs.onSurfaceVariant),
    };

    return Column(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, if (current != null) current],
            ),
            child: hero
                ? _Hero(
                    key: const ValueKey('hero'),
                    onPick: (c) => a.send(c),
                  )
                : ListView.builder(
                    key: const ValueKey('chat'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: count,
                    itemBuilder: (_, i) {
                      if (i < msgs.length) {
                        return _Bubble(msgs[i].text,
                            fromUser: msgs[i].fromUser);
                      }
                      return showTyping
                          ? _TypingBubble(t: _loop)
                          : _Bubble(a.partial, fromUser: true, ghost: true);
                    },
                  ),
          ),
        ),
        // Gợi ý nhanh (khi đã có hội thoại và đang rảnh).
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: (!hero && idle && !_typing)
              ? SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final s = _suggestions[i];
                      return ActionChip(
                        avatar: Icon(s.icon, size: 16, color: s.color),
                        label: Text(s.title),
                        onPressed: () => a.send(s.command),
                      );
                    },
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        // Ô gõ lệnh (dự phòng khi nói không rõ).
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: _typing
              ? _InputBar(
                  controller: _input,
                  focus: _focus,
                  enabled: idle,
                  onSend: () => _submitText(a),
                )
              : const SizedBox(width: double.infinity),
        ),
        _StatusPill(
          label: label,
          color: color,
          active: a.state == AssistantState.listening ||
              a.state == AssistantState.speaking,
          t: _loop,
        ),
        SizedBox(
          height: _VoiceOrb.box,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 64,
                child: Center(
                  child: IconButton.filledTonal(
                    tooltip: _typing ? 'Ẩn bàn phím' : 'Gõ lệnh',
                    onPressed: _toggleTyping,
                    icon: Icon(_typing
                        ? Icons.keyboard_hide_rounded
                        : Icons.keyboard_alt_outlined),
                  ),
                ),
              ),
              _VoiceOrb(
                state: a.state,
                t: _loop,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  a.toggleMic();
                },
              ),
              const SizedBox(width: 64),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── Màn chào ─────────────────────────────

class _Hero extends StatelessWidget {
  final void Function(String command) onPick;
  const _Hero({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final big = tt.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.15,
      letterSpacing: -0.5,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Reveal(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mình có thể giúp gì', style: big),
                GradientText('cho bạn hôm nay?',
                    gradient: Brand.aurora, style: big),
                const SizedBox(height: 10),
                Text(
                  'Nói tự nhiên bằng tiếng Việt — mình sẽ tạo việc, '
                  'xếp giờ và nhắc bạn đúng lúc.',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'GỢI Ý CHO BẠN',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.0,
            children: [
              for (var i = 0; i < _suggestions.length; i++)
                Reveal(
                  index: i + 1,
                  child: _SuggestionTile(
                    s: _suggestions[i],
                    onTap: () => onPick(_suggestions[i].command),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final _Suggestion s;
  final VoidCallback onTap;
  const _SuggestionTile({required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(s.icon, color: s.color, size: 22),
              ),
              const Spacer(),
              Text(
                s.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '“${s.command}”',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Ô gõ lệnh ─────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final VoidCallback onSend;
  const _InputBar({
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Glass(
        radius: 26,
        padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                enabled: enabled,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Hoặc gõ lệnh ở đây…',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            IconButton.filled(
              tooltip: 'Gửi',
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Trạng thái ─────────────────────────────

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final Animation<double> t;
  const _StatusPill({
    required this.label,
    required this.color,
    required this.active,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(label),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active)
              _Wave(t: t, color: color)
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sóng âm nhỏ khi đang nghe / đang đọc.
class _Wave extends StatelessWidget {
  final Animation<double> t;
  final Color color;
  const _Wave({required this.t, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              width: 3.5,
              height: 6 + 12 * (0.5 + 0.5 * math.sin(t.value * 4 * math.pi + i * 0.9)),
              margin: const EdgeInsets.symmetric(horizontal: 1.2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Bong bóng chat ─────────────────────────────

BoxDecoration _assistantBubble(BuildContext context, BorderRadius radius) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.92),
    borderRadius: radius,
    border: Border.all(
      color: dark
          ? Colors.white.withValues(alpha: 0.08)
          : Brand.violet.withValues(alpha: 0.10),
    ),
    boxShadow: [
      BoxShadow(
        color: Brand.violet.withValues(alpha: dark ? 0.0 : 0.06),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool fromUser;
  final bool ghost; // bong bóng tạm hiện lời đang nói
  const _Bubble(this.text, {required this.fromUser, this.ghost = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final solidUser = fromUser && !ghost;
    const big = Radius.circular(20);
    const small = Radius.circular(6);
    final radius = BorderRadius.only(
      topLeft: big,
      topRight: big,
      bottomLeft: fromUser ? big : small,
      bottomRight: fromUser ? small : big,
    );

    final decoration = fromUser
        ? BoxDecoration(
            gradient: solidUser ? Brand.gradient : null,
            color: solidUser ? null : Brand.violet.withValues(alpha: 0.14),
            borderRadius: radius,
            boxShadow: solidUser
                ? [
                    BoxShadow(
                      color: Brand.violet.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          )
        : _assistantBubble(context, radius);

    final bubble = Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: decoration,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15.5,
          height: 1.4,
          fontStyle: ghost ? FontStyle.italic : FontStyle.normal,
          color: solidUser ? Colors.white : cs.onSurface,
        ),
      ),
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment:
            fromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!fromUser) ...[const _Avatar(), const SizedBox(width: 8)],
          Flexible(child: bubble),
        ],
      ),
    );
    return ghost ? row : Reveal(child: row);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Brand.cyan, Brand.violet]),
        ),
        child: const Icon(Icons.auto_awesome_rounded,
            size: 16, color: Colors.white),
      );
}

class _TypingBubble extends StatelessWidget {
  final Animation<double> t;
  const _TypingBubble({required this.t});

  @override
  Widget build(BuildContext context) {
    const big = Radius.circular(20);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const _Avatar(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: _assistantBubble(
              context,
              const BorderRadius.only(
                topLeft: big,
                topRight: big,
                bottomRight: big,
                bottomLeft: Radius.circular(6),
              ),
            ),
            child: AnimatedBuilder(
              animation: t,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Transform.scale(
                        scale: 0.6 +
                            0.4 *
                                math.sin(((t.value * 2 + i * 0.18) % 1) *
                                    math.pi),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Brand.violet,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Quả cầu micro ─────────────────────────────

class _VoiceOrb extends StatelessWidget {
  static const double box = 164; // khung vẽ hiệu ứng
  static const double orb = 80; // đường kính nút micro

  final AssistantState state;
  final Animation<double> t;
  final VoidCallback onTap;
  const _VoiceOrb({required this.state, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (c1, c2, icon) = switch (state) {
      AssistantState.idle => (Brand.violet, Brand.cyan, Icons.mic_rounded),
      AssistantState.listening =>
        (Brand.pink, Brand.orange, Icons.stop_rounded),
      AssistantState.thinking =>
        (Brand.violet, Brand.blue, Icons.auto_awesome_rounded),
      AssistantState.speaking =>
        (Brand.cyan, Brand.green, Icons.graphic_eq_rounded),
    };

    final button = Semantics(
      button: true,
      label: state == AssistantState.listening ? 'Dừng nghe' : 'Nói với trợ lý',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          width: orb,
          height: orb,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c1, c2],
            ),
            boxShadow: [
              BoxShadow(
                color: c1.withValues(alpha: 0.55),
                blurRadius: 28,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Icon(icon, key: ValueKey(icon), size: 36, color: Colors.white),
          ),
        ),
      ),
    );

    final amp = switch (state) {
      AssistantState.idle => 0.02,
      AssistantState.listening => 0.05,
      AssistantState.speaking => 0.06,
      AssistantState.thinking => 0.0,
    };
    final speed = switch (state) {
      AssistantState.speaking => 3.0,
      AssistantState.listening => 2.0,
      _ => 1.0,
    };

    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: t,
                builder: (_, __) => CustomPaint(
                  painter: _OrbPainter(t.value, state, c1, c2),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: t,
            child: button,
            builder: (_, child) => Transform.scale(
              scale: 1 + amp * math.sin(t.value * 2 * math.pi * speed),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t;
  final AssistantState state;
  final Color c1;
  final Color c2;
  const _OrbPainter(this.t, this.state, this.c1, this.c2);

  static const double _r = _VoiceOrb.orb / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;

    switch (state) {
      case AssistantState.listening:
      case AssistantState.speaking:
        final rings = state == AssistantState.listening ? 3 : 2;
        for (var i = 0; i < rings; i++) {
          final p = (t + i / rings) % 1.0;
          final radius = _r + (maxR - _r) * Curves.easeOut.transform(p);
          canvas.drawCircle(
            c,
            radius,
            Paint()..color = c1.withValues(alpha: (1 - p) * 0.30),
          );
        }
      case AssistantState.thinking:
        final rect = Rect.fromCircle(center: c, radius: _r + 12);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [c1.withValues(alpha: 0), c1, c2],
            stops: const [0.0, 0.75, 1.0],
            transform: GradientRotation(t * 2 * math.pi),
          ).createShader(rect);
        canvas.drawCircle(c, _r + 12, paint);
      case AssistantState.idle:
        final glow = _r + 12 + 5 * math.sin(t * 2 * math.pi);
        canvas.drawCircle(c, glow, Paint()..color = c1.withValues(alpha: 0.16));
        canvas.drawCircle(
            c, _r + 26, Paint()..color = c1.withValues(alpha: 0.07));
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t || old.state != state || old.c1 != c1 || old.c2 != c2;
}