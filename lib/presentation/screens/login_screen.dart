import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';

import '../../features/auth/auth_service.dart';
import '../app_theme.dart';

class LoginScreen extends StatefulWidget {
  final AuthService auth;
  const LoginScreen({super.key, required this.auth});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() => _run(() async {
        final email = _email.text.trim();
        final pass = _password.text;
        if (_register) {
          await widget.auth.registerWithEmail(email, pass, _name.text.trim());
        } else {
          await widget.auth.signInWithEmail(email, pass);
        }
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Reveal(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: LogoMark(size: 92)),
                      const SizedBox(height: 22),
                      GradientText(
                        AppInfo.name,
                        textAlign: TextAlign.center,
                        gradient: Brand.aurora,
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppInfo.tagline,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Feature(Icons.mic_rounded, 'Nói tiếng Việt'),
                          _Feature(Icons.auto_awesome_rounded, 'Tự xếp lịch'),
                          _Feature(Icons.notifications_active_rounded,
                              'Nhắc đúng giờ'),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _register ? 'Tạo tài khoản mới' : 'Chào mừng trở lại',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 16),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: _register
                                    ? Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: TextField(
                                          controller: _name,
                                          decoration: const InputDecoration(
                                            labelText: 'Tên hiển thị',
                                            prefixIcon:
                                                Icon(Icons.person_rounded),
                                          ),
                                        ),
                                      )
                                    : const SizedBox(width: double.infinity),
                              ),
                              TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.mail_rounded),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _password,
                                obscureText: _obscure,
                                decoration: InputDecoration(
                                  labelText: 'Mật khẩu',
                                  prefixIcon: const Icon(Icons.lock_rounded),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                onSubmitted: (_) {
                                  if (!_busy) _submit();
                                },
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: _error == null
                                    ? const SizedBox(width: double.infinity)
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color:
                                                cs.error.withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.error_outline_rounded,
                                                  size: 18, color: cs.error),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _error!,
                                                  style:
                                                      TextStyle(color: cs.error),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 18),
                              FilledButton(
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.5),
                                      )
                                    : Text(_register ? 'Đăng ký' : 'Đăng nhập'),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  const Expanded(child: Divider()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Text('hoặc',
                                        style: TextStyle(
                                            color: cs.onSurfaceVariant)),
                                  ),
                                  const Expanded(child: Divider()),
                                ],
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                          await widget.auth.signInWithGoogle();
                                        }),
                                icon: const Icon(Icons.login_rounded),
                                label: const Text('Tiếp tục với Google'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!_register)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    final email = _email.text.trim();
                                    if (email.isEmpty) {
                                      throw FirebaseAuthException(
                                          code: 'invalid-email');
                                    }
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    await widget.auth.sendPasswordReset(email);
                                    messenger.showSnackBar(const SnackBar(
                                      content: Text(
                                          'Đã gửi email đặt lại mật khẩu.'),
                                    ));
                                  }),
                          child: const Text('Quên mật khẩu?'),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _register = !_register),
                        child: Text(_register
                            ? 'Đã có tài khoản? Đăng nhập'
                            : 'Chưa có tài khoản? Đăng ký'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Feature(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Brand.violet.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Brand.violet),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}