import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/analytics/data/performance_service.dart';
import '../../features/speech/voice_service.dart';

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  String _period = 'week';
  CoachReport? _report;
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final svc = context.read<PerformanceService>();
    try {
      final r = await svc.generate(_period);
      if (mounted) setState(() => _report = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<String>(
          segments: [
            for (final e in PerformanceService.periods.entries)
              ButtonSegment(value: e.key, label: Text(e.value)),
          ],
          selected: {_period},
          onSelectionChanged: (s) => setState(() {
            _period = s.first;
            _report = null;
          }),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _load,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.insights),
          label: const Text('Đánh giá hiệu suất'),
        ),
        if (r != null) ...[
          const SizedBox(height: 16),
          if (r.enoughData)
            Row(children: [
              _Stat('Đúng hạn', '${r.metrics.completionRate.round()}%'),
              _Stat('Quá hạn', '${r.metrics.overdueRate.round()}%'),
              _Stat('Giờ vàng', r.metrics.peakProductiveHours ?? '—'),
            ]),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.feedback),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () =>
                        context.read<VoiceService>().speak(r.feedback),
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Đọc to'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}
