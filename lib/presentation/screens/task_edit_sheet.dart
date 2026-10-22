import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../features/tasks/domain/app_task.dart';
import '../../features/tasks/domain/reminder_scheduler.dart';

/// Form thêm/sửa task bằng tay. Trả về AppTask cần lưu, hoặc null nếu hủy.
Future<AppTask?> showTaskEditSheet(BuildContext context, {AppTask? task}) {
  return showModalBottomSheet<AppTask>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _TaskForm(task: task),
    ),
  );
}

class _TaskForm extends StatefulWidget {
  final AppTask? task;
  const _TaskForm({this.task});

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  late final TextEditingController _title;
  late DateTime _due;
  late Priority _priority;
  late String? _repeat; // null | daily | weekly
  late int _duration;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    final n = DateTime.now();
    _due = t?.dueDate ?? DateTime(n.year, n.month, n.day, n.hour + 1);
    _priority = t?.priority ?? Priority.medium;
    _repeat = t?.isRecurring == true ? t?.recurrenceRule : null;
    _duration = t?.durationMinutes ?? 60;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (d != null) {
      setState(() => _due = DateTime(d.year, d.month, d.day, _due.hour, _due.minute));
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_due));
    if (t != null) {
      setState(() => _due = DateTime(_due.year, _due.month, _due.day, t.hour, t.minute));
    }
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final old = widget.task;
    final base = old ??
        AppTask(
          id: '',
          title: title,
          dueDate: _due,
          priority: _priority,
          notificationId: newNotificationId(),
          createdAt: DateTime.now(),
        );
    Navigator.pop(
      context,
      AppTask(
        id: base.id,
        title: title,
        dueDate: _due,
        priority: _priority,
        notificationId: base.notificationId,
        createdAt: base.createdAt,
        isCompleted: base.isCompleted,
        isRecurring: _repeat != null,
        recurrenceRule: _repeat,
        durationMinutes: _duration,
        completedAt: base.completedAt,
        rescheduleCount: base.rescheduleCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.task == null ? 'Công việc mới' : 'Sửa công việc',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            autofocus: widget.task == null,
            decoration: const InputDecoration(
                labelText: 'Tên công việc', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text(DateFormat('dd/MM/yyyy').format(_due)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule),
                label: Text(DateFormat('HH:mm').format(_due)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          SegmentedButton<Priority>(
            segments: const [
              ButtonSegment(value: Priority.high, label: Text('Cao')),
              ButtonSegment(value: Priority.medium, label: Text('Vừa')),
              ButtonSegment(value: Priority.low, label: Text('Thấp')),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _repeat,
                decoration: const InputDecoration(
                    labelText: 'Lặp lại', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Không')),
                  DropdownMenuItem(value: 'daily', child: Text('Hàng ngày')),
                  DropdownMenuItem(value: 'weekly', child: Text('Hàng tuần')),
                ],
                onChanged: (v) => setState(() => _repeat = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: [15, 30, 60, 90, 120].contains(_duration) ? _duration : 60,
                decoration: const InputDecoration(
                    labelText: 'Thời lượng', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('15 phút')),
                  DropdownMenuItem(value: 30, child: Text('30 phút')),
                  DropdownMenuItem(value: 60, child: Text('1 giờ')),
                  DropdownMenuItem(value: 90, child: Text('1,5 giờ')),
                  DropdownMenuItem(value: 120, child: Text('2 giờ')),
                ],
                onChanged: (v) => setState(() => _duration = v ?? 60),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Lưu')),
        ],
      ),
    );
  }
}
