import 'package:flutter_test/flutter_test.dart';
import 'package:voice_task_app/features/ai_engine/data/gemini_service.dart';
import 'package:voice_task_app/features/ai_engine/domain/ai_command.dart';
import 'package:voice_task_app/features/tasks/domain/app_task.dart';

void main() {
  test('decodeJsonLoose gỡ rào markdown và chữ thừa', () {
    final m = GeminiService.decodeJsonLoose(
        'Đây nhé:\n```json\n{"intent":"createTask","title":"Họp"}\n```');
    expect(m['title'], 'Họp');
  });

  test('decodeJsonLoose báo lỗi khi không có JSON', () {
    expect(() => GeminiService.decodeJsonLoose('xin chào'),
        throwsA(isA<GeminiException>()));
  });

  test('AiCommand.fromJson đọc đủ trường, ưu tiên mặc định', () {
    final c = AiCommand.fromJson({
      'intent': 'createTask',
      'title': ' Họp dự án FPT ',
      'dueDate': '2026-10-22T09:00:00+07:00',
      'priority': 'high',
      'durationMinutes': 90,
      'targetTaskIds': ['a', 'b'],
    });
    expect(c.intent, Intent.createTask);
    expect(c.title, 'Họp dự án FPT');
    expect(c.priority, Priority.high);
    expect(c.durationMinutes, 90);
    expect(c.targetTaskIds, ['a', 'b']);
    expect(c.dueDate!.toUtc(), DateTime.utc(2026, 10, 22, 2));
  });

  test('intent lạ → unknown, thiếu trường không lỗi', () {
    final c = AiCommand.fromJson({'intent': 'abc'});
    expect(c.intent, Intent.unknown);
    expect(c.dueDate, isNull);
    expect(c.targetTaskIds, isEmpty);
  });
}
