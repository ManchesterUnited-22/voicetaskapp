import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Tên và khẩu hiệu của app — sửa ở đây là đổi trên toàn bộ giao diện.
class AppInfo {
  static const name = 'Nói Là Xong';
  static const tagline = 'Trợ lý công việc bằng giọng nói';
}

/// Bảng màu thương hiệu dùng chung toàn app.
class Brand {
  static const violet = Color(0xFF7C5CFF);
  static const blue = Color(0xFF5C8AFF);
  static const cyan = Color(0xFF22D3EE);
  static const pink = Color(0xFFFF5C8A);
  static const orange = Color(0xFFFF9A5C);
  static const green = Color(0xFF34D399);
  static const gold = Color(0xFFE0A100);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, blue],
  );

  static const aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, blue, cyan],
  );
  static const warm = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [pink, orange],
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final cs =
      ColorScheme.fromSeed(seedColor: Brand.violet, brightness: brightness);
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide(color: Brand.violet.withValues(alpha: 0.15)),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF0E0B1F) : const Color(0xFFF6F4FF),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 72,
      titleTextStyle: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: cs.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent,
      color: dark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.88),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : Brand.violet.withValues(alpha: 0.10),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Brand.violet.withValues(alpha: dark ? 0.32 : 0.16),
      indicatorShape: const StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: BorderSide(color: cs.outlineVariant),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: Brand.violet.withValues(alpha: 0.22)),
      showCheckmark: false,
      selectedColor: Brand.violet.withValues(alpha: dark ? 0.35 : 0.16),
      backgroundColor: dark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.9),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        side: WidgetStatePropertyAll(
          BorderSide(color: Brand.violet.withValues(alpha: 0.25)),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? const Color(0xFF1C1740) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: DividerThemeData(
      color: Brand.violet.withValues(alpha: 0.12),
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: dark ? const Color(0xFF17132E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
    ),
  );
}

/// Nền gradient mềm + các vệt sáng mờ phía sau nội dung.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF0E0B1F), Color(0xFF151033), Color(0xFF0B1426)]
                  : const [Color(0xFFF4F1FF), Color(0xFFEAF4FF), Color(0xFFFFF1F6)],
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -70,
          child: _Blob(Brand.violet.withValues(alpha: dark ? 0.28 : 0.20), 280),
        ),
        Positioned(
          bottom: 100,
          left: -100,
          child: _Blob(Brand.cyan.withValues(alpha: dark ? 0.16 : 0.18), 260),
        ),
        Positioned(
          bottom: -60,
          right: -80,
          child: _Blob(Brand.pink.withValues(alpha: dark ? 0.12 : 0.14), 220),
        ),
        child,
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob(this.color, this.size);

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      );
}

/// Hiện dần + trượt nhẹ lên khi xuất hiện. [index] lớn hơn thì chậm hơn một chút.
class Reveal extends StatelessWidget {
  final Widget child;
  final int index;
  const Reveal({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + 70 * index.clamp(0, 8)),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: c),
      ),
      child: child,
    );
  }
}

/// Khối kính mờ (dùng cho thanh điều hướng, ô nhập...).
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.blur = 18,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Brand.violet.withValues(alpha: dark ? 0.22 : 0.12),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: dark
                  ? const Color(0xFF1A1536).withValues(alpha: 0.78)
                  : Colors.white.withValues(alpha: 0.80),
              borderRadius: r,
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Brand.violet.withValues(alpha: 0.12),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Logo app: ô bo góc gradient, micro + tia sáng.
class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.violet, Brand.cyan],
        ),
        boxShadow: [
          BoxShadow(
            color: Brand.violet.withValues(alpha: 0.42),
            blurRadius: size * 0.45,
            offset: Offset(0, size * 0.18),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.mic_rounded, size: size * 0.52, color: Colors.white),
          Positioned(
            top: size * 0.14,
            right: size * 0.14,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: size * 0.22,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chữ tô gradient.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient gradient;
  final TextAlign? textAlign;
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient = Brand.gradient,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) =>
          gradient.createShader(Rect.fromLTWH(0, 0, r.width, r.height)),
      child: Text(text, textAlign: textAlign, style: style),
    );
  }
}