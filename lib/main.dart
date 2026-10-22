import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'features/ai_engine/data/gemini_service.dart';
import 'features/ai_engine/domain/command_handler.dart';
import 'features/analytics/data/performance_service.dart';
import 'features/auth/auth_service.dart';
import 'features/notifications/notification_service.dart';
import 'features/speech/voice_service.dart';
import 'features/tasks/data/firestore_task_repository.dart';
import 'features/tasks/domain/reminder_scheduler.dart';
import 'features/tasks/domain/task_repository.dart';
import 'firebase_options.dart';
import 'presentation/app_theme.dart';
import 'presentation/assistant_provider.dart';
import 'presentation/home_shell.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/task_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('vi_VN');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final notifications = NotificationService();
  await notifications.init();
  runApp(App(notifications: notifications));
}

class App extends StatelessWidget {
  final NotificationService notifications;
  const App({super.key, required this.notifications});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    return MaterialApp(
      title: 'Trợ lý công việc giọng nói',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('vi', 'VN'),
      supportedLocales: const [Locale('vi', 'VN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: StreamBuilder<User?>(
        stream: auth.authState,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _Splash();
          }
          final user = snap.data;
          if (user == null) return LoginScreen(auth: auth);
          // key theo uid: đổi tài khoản thì dựng lại toàn bộ dịch vụ.
          return SessionScope(
            key: ValueKey(user.uid),
            uid: user.uid,
            auth: auth,
            notifications: notifications,
          );
        },
      ),
    );
  }
}

/// Màn hình chờ khi đang kiểm tra đăng nhập.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: Brand.gradient,
                boxShadow: [
                  BoxShadow(
                    color: Brand.violet.withValues(alpha: 0.5),
                    blurRadius: 36,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(Icons.mic_rounded, size: 44, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dựng các dịch vụ gắn với một người dùng đã đăng nhập.
class SessionScope extends StatelessWidget {
  final String uid;
  final AuthService auth;
  final NotificationService notifications;
  const SessionScope({
    super.key,
    required this.uid,
    required this.auth,
    required this.notifications,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<TaskRepository>(create: (_) => FirestoreTaskRepository(uid)),
        Provider<ReminderScheduler>.value(value: notifications),
        Provider<GeminiService>(create: (_) => GeminiService()),
        Provider<VoiceService>(create: (_) => VoiceService()),
        ProxyProvider2<TaskRepository, GeminiService, PerformanceService>(
          update: (_, repo, gemini, __) => PerformanceService(repo, gemini),
        ),
        ChangeNotifierProvider<TaskProvider>(
          create: (c) =>
              TaskProvider(c.read<TaskRepository>(), c.read<ReminderScheduler>()),
        ),
        ChangeNotifierProvider<AssistantProvider>(
          create: (c) {
            final perf = c.read<PerformanceService>();
            final handler = CommandHandler(
              parser: c.read<GeminiService>(),
              repo: c.read<TaskRepository>(),
              reminders: c.read<ReminderScheduler>(),
              performanceReply: (period) async =>
                  (await perf.generate(period)).feedback,
            );
            return AssistantProvider(handler, c.read<VoiceService>());
          },
        ),
      ],
      child: _DailyCoachTrigger(
        notifications: notifications,
        child: HomeShell(auth: auth),
      ),
    );
  }
}

/// Chạy nhận xét cuối ngày một lần khi vào app (chạy nền đúng 20h cần workmanager — chưa làm).
class _DailyCoachTrigger extends StatefulWidget {
  final NotificationService notifications;
  final Widget child;
  const _DailyCoachTrigger({required this.notifications, required this.child});

  @override
  State<_DailyCoachTrigger> createState() => _DailyCoachTriggerState();
}

class _DailyCoachTriggerState extends State<_DailyCoachTrigger> {
  @override
  void initState() {
    super.initState();
    final perf = context.read<PerformanceService>();
    perf.maybeDailyCoach(widget.notifications.showNow).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}