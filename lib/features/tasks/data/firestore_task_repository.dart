import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/app_task.dart';
import '../domain/task_repository.dart';

/// users/{uid}/tasks, users/{uid}/voice_logs, users/{uid}/performance_analytics
class FirestoreTaskRepository implements TaskRepository {
  final String uid;
  final FirebaseFirestore _db;
  FirestoreTaskRepository(this.uid, {FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _user =>
      _db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get _tasks =>
      _user.collection('tasks');

  AppTask _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      AppTask.fromMap(d.id, d.data());

  @override
  Stream<List<AppTask>> watchTasks() => _tasks
      .orderBy('dueDate')
      .snapshots()
      .map((s) => s.docs.map(_fromDoc).toList());

  @override
  Future<List<AppTask>> getAll() async {
    final s = await _tasks.orderBy('dueDate').get();
    return s.docs.map(_fromDoc).toList();
  }

  @override
  Future<List<AppTask>> getBetween(DateTime from, DateTime to) async {
    final s = await _tasks
        .where('dueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('dueDate', isLessThan: Timestamp.fromDate(to))
        .orderBy('dueDate')
        .get();
    return s.docs.map(_fromDoc).toList();
  }

  @override
  Future<AppTask> add(AppTask task) async {
    final ref = _tasks.doc();
    final saved = AppTask(
      id: ref.id,
      title: task.title,
      dueDate: task.dueDate,
      priority: task.priority,
      notificationId: task.notificationId,
      createdAt: task.createdAt,
      isCompleted: task.isCompleted,
      isRecurring: task.isRecurring,
      recurrenceRule: task.recurrenceRule,
      durationMinutes: task.durationMinutes,
      completedAt: task.completedAt,
      rescheduleCount: task.rescheduleCount,
    );
    await ref.set(saved.toMap());
    return saved;
  }

  @override
  Future<void> update(AppTask task) => _tasks.doc(task.id).set(task.toMap());

  @override
  Future<void> delete(String id) => _tasks.doc(id).delete();

  @override
  Future<void> logVoice({required String rawText, required String intent}) =>
      _user.collection('voice_logs').add({
        'rawAudioText': rawText,
        'detectedIntent': intent,
        'timestamp': FieldValue.serverTimestamp(),
      });

  @override
  Future<DateTime?> getLastDailyCoach() async {
    final s = await _user.get();
    return (s.data()?['lastDailyCoach'] as Timestamp?)?.toDate();
  }

  @override
  Future<void> setLastDailyCoach(DateTime d) =>
      _user.set({'lastDailyCoach': Timestamp.fromDate(d)}, SetOptions(merge: true));

  @override
  Future<void> saveAnalytics(Map<String, dynamic> data) =>
      _user.collection('performance_analytics').add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
  CollectionReference<Map<String, dynamic>> get _activity =>
    _user.collection('activity_logs');

@override
Future<void> saveActivity(Map<String, dynamic> data) =>
    _activity.doc(data['id'] as String).set({
      ...data,
      'at': Timestamp.fromDate(data['at'] as DateTime),
      'createdAt': FieldValue.serverTimestamp(),
    });

@override
Future<void> markActivityUndone(String id) =>
    _activity.doc(id).update({'undone': true});

@override
Future<List<Map<String, dynamic>>> loadActivity({int limit = 30}) async {
  final s = await _activity.orderBy('at', descending: true).limit(limit).get();
  return s.docs.map((d) {
    final m = d.data();
    return {...m, 'id': d.id, 'at': (m['at'] as Timestamp).toDate()};
  }).toList();
}
}
