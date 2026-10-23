import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'features/ai_engine/data/gemini_service.dart';
import 'features/activity/domain/activity_log.dart';
import 'features/ai_engine/domain/command_handler.dart';
import 'features/analytics/data/performance_service.dart';
import 'features/auth/auth_service.dart';
import 'core/config.dart';
import 'features/tasks/data/demo_task_repository.dart';
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
      title: AppInfo.name,
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: AppBackground(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LogoMark(size: 96),
                const SizedBox(height: 20),
                GradientText(
                  AppInfo.name,
                  gradient: Brand.aurora,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppInfo.tagline,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
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
        Provider<TaskRepository>(
            create: (_) => AppConfig.demoData
                ? DemoTaskRepository()
                : FirestoreTaskRepository(uid)),
        Provider<ReminderScheduler>.value(value: notifications),
        Provider<GeminiService>(create: (_) => GeminiService()),
        Provider<VoiceService>(create: (_) => VoiceService()),
        ProxyProvider2<TaskRepository, GeminiService, PerformanceService>(
          update: (_, repo, gemini, __) => PerformanceService(repo, gemini),
        ),
        // Nhật ký hoạt động dùng chung: RAM + Firestore users/{uid}/activity_logs.
        Provider<ActivityLog>(
          create: (c) => ActivityLog(c.read<TaskRepository>())..load(),
        ),
        ChangeNotifierProvider<TaskProvider>(
          create: (c) => TaskProvider(
              c.read<TaskRepository>(), c.read<ReminderScheduler>(),
              log: c.read<ActivityLog>()),
        ),
        ChangeNotifierProvider<AssistantProvider>(
          create: (c) {
            final perf = c.read<PerformanceService>();
            final handler = CommandHandler(
              parser: c.read<GeminiService>(),
              repo: c.read<TaskRepository>(),
              reminders: c.read<ReminderScheduler>(),
              log: c.read<ActivityLog>(),
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
  const _DailyCoachTrigger(
      {required this.notifications, required this.child});

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