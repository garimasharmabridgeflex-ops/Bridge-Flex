import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// KFlex brand palette. Oxford Navy for high-trust institutional authority,
/// Slate Blue for interactive elements, Soft Porcelain for canvas, and
/// Emerald for verified/paid states (Stitch Design System).
abstract final class AppColors {
  // Oxford Navy & Dark Slate
  static const Color oxford = Color(0xFF1B2A4A);
  static const Color oxfordDark = Color(0xFF0F172A);
  static const Color primary = Color(0xFF1B2A4A);
  static const Color primaryDark = Color(0xFF0F172A);
  static const Color primaryLight = Color(0xFF2D426E);

  // Backward-compatibility aliases
  static const Color indigo = Color(0xFF1B2A4A);
  static const Color indigoDeep = Color(0xFF0F172A);
  static const Color teal = Color(0xFF059669);

  // Slate Blue Accent
  static const Color slateBlue = Color(0xFF2563EB);
  static const Color slateBlueMuted = Color(0xFF3B82F6);
  static const Color secondary = Color(0xFF2563EB);

  // Status & Utility Colors
  static const Color emerald = Color(0xFF059669);
  static const Color mint = Color(0xFF10B981);
  static const Color amber = Color(0xFFD97706);
  static const Color coral = Color(0xFFDC2626);
  static const Color rose = Color(0xFFE11D48);

  // Porcelain Canvas & Tonal Layering
  static const Color porcelain = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFF8FAFC);
  static const Color surfaceDark = Color(0xFF0F172A);
  static const Color cardDark = Color(0xFF1E293B);
  static const Color outlineSubtle = Color(0xFFE2E8F0);
}

abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double card = 24;
  static const double pill = 999;
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppTheme {
  AppTheme._();

  static TextTheme _textTheme(Color color) {
    return GoogleFonts.plusJakartaSansTextTheme().apply(
      bodyColor: color,
      displayColor: color,
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.oxford,
      brightness: Brightness.light,
      primary: AppColors.oxford,
      secondary: AppColors.slateBlue,
      surface: Colors.white,
    );
    return _base(scheme, AppColors.porcelain);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.oxford,
      brightness: Brightness.dark,
      primary: const Color(0xFF93C5FD),
      secondary: AppColors.slateBlueMuted,
      surface: AppColors.cardDark,
    );
    return _base(scheme, AppColors.surfaceDark);
  }

  static ThemeData _base(ColorScheme scheme, Color scaffoldBg) {
    final textTheme = _textTheme(scheme.onSurface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SmoothFadeThroughTransitionsBuilder(),
          TargetPlatform.iOS: _SmoothFadeThroughTransitionsBuilder(),
          TargetPlatform.macOS: _SmoothFadeThroughTransitionsBuilder(),
          TargetPlatform.linux: _SmoothFadeThroughTransitionsBuilder(),
          TargetPlatform.windows: _SmoothFadeThroughTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: AppColors.outlineSubtle.withValues(alpha: 0.6)),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        side: BorderSide.none,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}

/// A gentle fade + vertical-slide transition, reused for every route so
/// navigation throughout the app feels like one coherent motion language.
class _SmoothFadeThroughTransitionsBuilder extends PageTransitionsBuilder {
  const _SmoothFadeThroughTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final secondaryCurved = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0.92).animate(secondaryCurved),
          child: child,
        ),
      ),
    );
  }
}
