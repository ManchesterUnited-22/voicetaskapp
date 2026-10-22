import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../assistant_provider.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final AnimationController _loop;
  int _lastItems = 0;

  static const _suggestions = [
    'Sáng mai 9h họp dự án',
    'Hôm nay tôi có việc gì?',
    'Đánh giá hiệu suất tuần này',
  ];

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

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AssistantProvider>();
    final cs = Theme.of(context).colorScheme;
    final msgs = a.messages;
    final showTyping = a.state == AssistantState.thinking;
    final showPartial =
        a.state == AssistantState.listening && a.partial.isNotEmpty;
    final count = msgs.length + (showTyping || showPartial ? 1 : 0);

    if (count != _lastItems) {
      _lastItems = count;
      _scrollDown();
    }

    final (label, color) = switch (a.state) {
      AssistantState.listening => ('Đang nghe…', Brand.pink),
      AssistantState.thinking => ('Đang suy nghĩ…', cs.primary),
      AssistantState.speaking => ('Đang trả lời…', const Color(0xFF0891B2)),
      AssistantState.idle => ('Chạm vào micro để nói', cs.onSurfaceVariant),
    };

    final showSuggestions =
        msgs.length <= 1 && a.state == AssistantState.idle;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            itemCount: count,
            itemBuilder: (_, i) {
              if (i < msgs.length) {
                return _Bubble(msgs[i].text, fromUser: msgs[i].fromUser);
              }
              return showTyping
                  ? _TypingBubble(t: _loop)
                  : _Bubble(a.partial, fromUser: true, ghost: true);
            },
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: showSuggestions
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in _suggestions)
                          ActionChip(
                            label: Text(s),
                            avatar:
                                const Icon(Icons.north_east_rounded, size: 14),
                            onPressed: () => a.send(s),
                          ),
                      ],
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Padding(
            key: ValueKey(a.state),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
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
      ],
    );
  }
}

// ───────────────────────────── Bong bóng chat ─────────────────────────────

BoxDecoration _assistantBubble(BuildContext context, BorderRadius radius) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.9),
    borderRadius: radius,
    border: Border.all(
      color: dark
          ? Colors.white.withValues(alpha: 0.08)
          : Brand.violet.withValues(alpha: 0.10),
    ),
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

    final orb = Semantics(
      button: true,
      label: state == AssistantState.listening ? 'Dừng nghe' : 'Nói với trợ lý',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          width: 96,
          height: 96,
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
                blurRadius: 30,
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
            child: Icon(icon, key: ValueKey(icon), size: 42, color: Colors.white),
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
      width: 220,
      height: 220,
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
            child: orb,
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

  static const double _r = 48;

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
        final rect = Rect.fromCircle(center: c, radius: _r + 14);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [c1.withValues(alpha: 0), c1, c2],
            stops: const [0.0, 0.75, 1.0],
            transform: GradientRotation(t * 2 * math.pi),
          ).createShader(rect);
        canvas.drawCircle(c, _r + 14, paint);
      case AssistantState.idle:
        final glow = _r + 14 + 6 * math.sin(t * 2 * math.pi);
        canvas.drawCircle(c, glow, Paint()..color = c1.withValues(alpha: 0.16));
        canvas.drawCircle(
            c, _r + 30, Paint()..color = c1.withValues(alpha: 0.07));
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t || old.state != state || old.c1 != c1 || old.c2 != c2;
}