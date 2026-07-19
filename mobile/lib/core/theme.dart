import 'dart:math' as math;

import 'package:flutter/material.dart';

abstract final class BraveColors {
  static const midnight = Color(0xFF071A31);
  static const polar = Color(0xFFF2FBFF);
  static const ice = Color(0xFFD7F3FC);
  static const aurora = Color(0xFF6FE0C8);
  static const auroraDeep = Color(0xFF2EA79A);
  static const coral = Color(0xFFFF8D78);
  static const ink = Color(0xFF102D49);
  static const mist = Color(0xFF7390A5);
  static const warning = Color(0xFFFFC96B);
}

ThemeData braveTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: BraveColors.auroraDeep,
        brightness: Brightness.light,
        surface: BraveColors.polar,
      ).copyWith(
        primary: BraveColors.auroraDeep,
        secondary: BraveColors.coral,
        onSurface: BraveColors.ink,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: BraveColors.polar,
    fontFamily: 'serif',
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
      headlineLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .4),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800),
      titleLarge: TextStyle(fontWeight: FontWeight.w800),
      bodyLarge: TextStyle(height: 1.55),
      bodyMedium: TextStyle(height: 1.5),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BraveColors.coral,
        foregroundColor: BraveColors.midnight,
        minimumSize: const Size(64, 54),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        shape: const StadiumBorder(),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        borderSide: BorderSide(color: Color(0xFFD1E8F0)),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
  );
}

class AuroraBackground extends StatelessWidget {
  const AuroraBackground({required this.child, super.key, this.dark = true});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: dark
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF06182D),
                      Color(0xFF0C3B59),
                      Color(0xFF102A4D),
                    ],
                  )
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFEAF9FF), Color(0xFFF7FCFF)],
                  ),
          ),
        ),
        Positioned(
          top: -120,
          left: -80,
          right: -60,
          height: 360,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: -.16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(200),
                  gradient: LinearGradient(
                    colors: [
                      BraveColors.aurora.withValues(alpha: dark ? .34 : .18),
                      const Color(0xFF8BC8FF).withValues(alpha: .12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        CustomPaint(painter: SnowPainter(dark: dark)),
        child,
      ],
    );
  }
}

class SnowPainter extends CustomPainter {
  SnowPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (dark ? Colors.white : BraveColors.auroraDeep).withValues(
        alpha: .17,
      );
    final random = math.Random(7719);
    for (var index = 0; index < 46; index++) {
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      canvas.drawCircle(point, 1 + random.nextDouble() * 2.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SnowPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class SnowFoxMark extends StatelessWidget {
  const SnowFoxMark({super.key, this.size = 86});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: BraveColors.ice,
        borderRadius: BorderRadius.circular(size * .36),
        boxShadow: const [
          BoxShadow(color: Color(0x446FE0C8), blurRadius: 30, spreadRadius: 4),
        ],
      ),
      child: CustomPaint(painter: _FoxPainter()),
    );
  }
}

class _FoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    final coral = Paint()..color = BraveColors.coral;
    final ink = Paint()..color = BraveColors.ink;
    final face = Path()
      ..moveTo(size.width * .18, size.height * .26)
      ..lineTo(size.width * .38, size.height * .12)
      ..lineTo(size.width * .48, size.height * .29)
      ..lineTo(size.width * .65, size.height * .13)
      ..lineTo(size.width * .82, size.height * .34)
      ..quadraticBezierTo(
        size.width * .86,
        size.height * .77,
        size.width * .5,
        size.height * .85,
      )
      ..quadraticBezierTo(
        size.width * .12,
        size.height * .72,
        size.width * .18,
        size.height * .26,
      )
      ..close();
    canvas.drawPath(face, white);
    final cheek = Path()
      ..moveTo(size.width * .21, size.height * .45)
      ..quadraticBezierTo(
        size.width * .5,
        size.height * .82,
        size.width * .79,
        size.height * .45,
      )
      ..quadraticBezierTo(
        size.width * .64,
        size.height * .91,
        size.width * .5,
        size.height * .88,
      )
      ..quadraticBezierTo(
        size.width * .34,
        size.height * .91,
        size.width * .21,
        size.height * .45,
      );
    canvas.drawPath(cheek, coral);
    canvas.drawCircle(
      Offset(size.width * .38, size.height * .48),
      size.width * .035,
      ink,
    );
    canvas.drawCircle(
      Offset(size.width * .64, size.height * .48),
      size.width * .035,
      ink,
    );
    canvas.drawCircle(
      Offset(size.width * .51, size.height * .62),
      size.width * .045,
      ink,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FrostedPanel extends StatelessWidget {
  const FrostedPanel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: .72),
          width: 1.4,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2203192B),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}
