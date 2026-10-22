import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/vi_text.dart';
import '../../core/format.dart';
import '../../features/tasks/domain/app_task.dart';
import '../app_theme.dart';
import '../task_provider.dart';
import 'task_edit_sheet.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TaskProvider>();
    if (p.error != null) return _ErrorState(message: friendlyError(p.error!));
    if (p.all.isEmpty) return const _EmptyState();

    final now = DateTime.now();
    final sections = <(String, List<AppTask>, Color)>[
      ('Quá hạn', p.overdue, Brand.pink),
      ('Sắp tới', p.upcoming, Brand.violet),
      ('Đã hoàn thành', p.completed, Brand.green),
    ].where((s) => s.$2.isNotEmpty).toList();

    var index = 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Reveal(
          child: _SummaryCard(
            done: p.completed.length,
            total: p.all.length,
            overdue: p.overdue.length,
          ),
        ),
        for (final s in sections) ...[
          _SectionHeader(title: s.$1, count: s.$2.length, color: s.$3),
          for (final t in s.$2)
            Reveal(
              key: ValueKey('r_${t.id}'),
              index: index++,
              child: _TaskCard(
                task: t,
                now: now,
                accent: s.$3,
                onToggle: () => p.toggle(t),
                onDelete: () => p.remove(t),
                onTap: () => _edit(context, p, t),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _edit(BuildContext context, TaskProvider p, AppTask t) async {
    final r = await showTaskEditSheet(context, task: t);
    if (r != null) await p.save(r);
  }
}

// ───────────────────────────── Thẻ tiến độ ─────────────────────────────

class _SummaryCard extends StatelessWidget {
  final int done;
  final int total;
  final int overdue;
  const _SummaryCard(
      {required this.done, required this.total, required this.overdue});

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : done / total;
    final pending = total - done;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: Brand.gradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Brand.violet.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pending == 0 ? 'Tuyệt vời! Xong hết rồi' : 'Còn $pending việc cần làm',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$done/$total hoàn thành',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (overdue > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$overdue quá hạn',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionHeader(
      {required this.title, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Thẻ công việc ─────────────────────────────

class _TaskCard extends StatelessWidget {
  final AppTask task;
  final DateTime now;
  final Color accent;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  const _TaskCard({
    required this.task,
    required this.now,
    required this.accent,
    required this.onToggle,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = task;
    final overdue = t.isOverdue(now);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Dismissible(
        key: ValueKey('d_${t.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: Brand.pink,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        onDismissed: (_) => onDelete(),
        child: AnimatedOpacity(
          opacity: t.isCompleted ? 0.6 : 1,
          duration: const Duration(milliseconds: 300),
          child: Card(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    _CheckCircle(
                      done: t.isCompleted,
                      accent: accent,
                      onTap: onToggle,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 250),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium!
                                .copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: t.isCompleted
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                  color: t.isCompleted
                                      ? cs.onSurfaceVariant
                                      : cs.onSurface,
                                ),
                            child: Text(
                              t.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 14,
                                color: overdue ? Brand.pink : cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  formatDateTimeVi(t.dueDate, now),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: overdue
                                        ? Brand.pink
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (t.isRecurring) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.repeat_rounded,
                                    size: 14, color: cs.onSurfaceVariant),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PriorityPill(t.priority),
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

class _CheckCircle extends StatelessWidget {
  final bool done;
  final Color accent;
  final VoidCallback onTap;
  const _CheckCircle(
      {required this.done, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: done ? Brand.gradient : null,
            border: done ? null : Border.all(color: accent, width: 2),
          ),
          child: AnimatedScale(
            scale: done ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child:
                const Icon(Icons.check_rounded, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _PriorityPill extends StatelessWidget {
  final Priority priority;
  const _PriorityPill(this.priority);

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (priority) {
      Priority.high => (Brand.pink, 'Cao'),
      Priority.medium => (const Color(0xFFD99A00), 'Vừa'),
      Priority.low => (Brand.blue, 'Thấp'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ───────────────────────────── Trạng thái rỗng / lỗi ─────────────────────────────

class _EmptyState extends StatefulWidget {
  const _EmptyState();

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, -10 * Curves.easeInOut.transform(_c.value)),
                child: child,
              ),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: Brand.gradient,
                  boxShadow: [
                    BoxShadow(
                      color: Brand.violet.withValues(alpha: 0.4),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(Icons.mic_rounded,
                    size: 42, color: Colors.white),
              ),
            ),
            const SizedBox(height: 28),
            Text('Chưa có công việc nào',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Sang tab Trợ lý, chạm micro và nói:\n“Sáng mai 9h họp dự án”',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: cs.error),
            const SizedBox(height: 16),
            Text('Không tải được dữ liệu',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}