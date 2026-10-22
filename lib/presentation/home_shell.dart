import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/auth/auth_service.dart';
import 'app_theme.dart';
import 'screens/assistant_screen.dart';
import 'screens/tasks_screen.dart';

class HomeShell extends StatefulWidget {
  final AuthService auth;
  const HomeShell({super.key, required this.auth});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['Trợ lý', 'Công việc'];
  static const _subtitles = [
    'Nói là xong, mọi việc để mình lo',
    'Tất cả việc cần làm của bạn',
    'Phân tích và gợi ý cải thiện',
  ];
  static const _pages = <Widget>[
    AssistantScreen(),
    TasksScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, if (current != null) current],
            ),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(_index),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titles[_index],
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  _subtitles[_index],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton.filledTonal(
                tooltip: 'Đăng xuất',
                icon: const Icon(Icons.logout_rounded),
                onPressed: widget.auth.signOut,
              ),
            ),
          ],
        ),
        // Giữ nguyên trạng thái các tab, nhưng chuyển tab có hiệu ứng mờ + trượt.
        body: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < _pages.length; i++)
              IgnorePointer(
                ignoring: i != _index,
                child: ExcludeSemantics(
                  excluding: i != _index,
                  child: AnimatedOpacity(
                    opacity: i == _index ? 1 : 0,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    child: AnimatedSlide(
                      offset: i == _index
                          ? Offset.zero
                          : Offset(i < _index ? -0.04 : 0.04, 0),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      // Tab đang ẩn thì tắt animation để đỡ tốn pin.
                      child: TickerMode(enabled: i == _index, child: _pages[i]),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark
                  ? const Color(0xFF1A1536).withValues(alpha: 0.94)
                  : Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Brand.violet.withValues(alpha: 0.10),
              ),
              boxShadow: [
                BoxShadow(
                  color: Brand.violet.withValues(alpha: dark ? 0.25 : 0.15),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) {
                    HapticFeedback.selectionClick();
                    setState(() => _index = i);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.mic_none_rounded),
                      selectedIcon: Icon(Icons.mic_rounded),
                      label: 'Trợ lý',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.checklist_rounded),
                      selectedIcon: Icon(Icons.task_alt_rounded),
                      label: 'Công việc',
                    ),
                   
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}