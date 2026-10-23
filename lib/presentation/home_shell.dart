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

  static const _pages = <Widget>[
    AssistantScreen(),
    TasksScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(auth: widget.auth),
              Expanded(
                // Giữ nguyên trạng thái các tab, chuyển tab có hiệu ứng mờ + trượt.
                child: Stack(
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
                              child: TickerMode(
                                enabled: i == _index,
                                child: _pages[i],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: _NavBar(
            index: _index,
            onChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => _index = i);
            },
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Header ─────────────────────────────

String _greeting(DateTime n) {
  final h = n.hour;
  if (h < 11) return 'Chào buổi sáng';
  if (h < 14) return 'Chào buổi trưa';
  if (h < 18) return 'Chào buổi chiều';
  return 'Chào buổi tối';
}

String _shortName(String? displayName, String? email) {
  final n = displayName?.trim() ?? '';
  if (n.isNotEmpty) return n.split(RegExp(r'\s+')).last;
  final e = email ?? '';
  if (e.contains('@')) return e.split('@').first;
  return 'bạn';
}

class _Header extends StatelessWidget {
  final AuthService auth;
  const _Header({required this.auth});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = auth.currentUser;
    final name = _shortName(user?.displayName, user?.email);
    final initial =
        name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 6),
      child: Row(
        children: [
          const LogoMark(size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GradientText(
                  AppInfo.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_greeting(DateTime.now())}, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Tài khoản',
            offset: const Offset(0, 52),
            onSelected: (v) {
              if (v == 'out') auth.signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName?.trim().isNotEmpty == true
                          ? user!.displayName!
                          : name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    if ((user?.email ?? '').isNotEmpty)
                      Text(
                        user!.email!,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'out',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('Đăng xuất'),
                  ],
                ),
              ),
            ],
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: Brand.warm,
                boxShadow: [
                  BoxShadow(
                    color: Brand.pink.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Thanh điều hướng ─────────────────────────────

class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _NavBar({required this.index, required this.onChanged});

  static const _items = [
    (Icons.mic_none_rounded, Icons.mic_rounded, 'Trợ lý'),
    (Icons.checklist_rounded, Icons.task_alt_rounded, 'Công việc'),
  ];

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 30,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: _NavItem(
                icon: _items[i].$1,
                selectedIcon: _items[i].$2,
                label: _items[i].$3,
                selected: i == index,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? Colors.white : cs.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          height: 52,
          decoration: BoxDecoration(
            gradient: selected ? Brand.gradient : null,
            borderRadius: BorderRadius.circular(24),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Brand.violet.withValues(alpha: 0.38),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? selectedIcon : icon, size: 22, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}