import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Central design tokens for Funny You.
///
/// Brand palette is black + red, minimal. The primary audience is older users,
/// so body copy never drops below 15pt and interactive targets never below 52pt.
///
/// Readability rule: red is for buttons, highlights and accents only — never for
/// body text. Red on black is ~5:1 contrast vs ~19:1 for white on black, and red
/// is a dark hue, so it gives ageing eyes less light. Text is white/grey.
abstract final class AppColors {
  /// Brand red. Matches the app icon background.
  static const primary = Color(0xFFE11D28);
  static const primaryDark = Color(0xFFB3141D);

  /// Brighter red for small accents on black, where more luminance helps.
  static const primaryBright = Color(0xFFFF4B54);

  /// Red-tinted dark fills (chips, selected states) — replaces the old light tints.
  static const primaryTint = Color(0xFF3A1013);
  static const primarySoft = Color(0xFF24090B);

  /// Backgrounds, darkest to lightest.
  static const cream = Color(0xFF000000);
  static const lavender = Color(0xFF0A0A0A);
  static const surface = Color(0xFF141414);
  static const surfaceAlt = Color(0xFF1C1C1C);

  /// Text. `ink` is the primary reading colour and is deliberately pure white.
  static const ink = Color(0xFFFFFFFF);
  static const inkSoft = Color(0xFFC9C9C9);
  static const inkMuted = Color(0xFF8C8C8C);
  static const hairline = Color(0xFF2A2A2A);

  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFFFB020);
  static const danger = Color(0xFFFF4B54);

  static const shimmerBase = Color(0xFF1C1C1C);
  static const shimmerHighlight = Color(0xFF2A2A2A);

  /// Text/icon colour that sits on top of a red fill.
  static const onPrimary = Color(0xFFFFFFFF);
}

abstract final class AppRadius {
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const pill = 999.0;
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 44.0;
}

abstract final class AppShadows {
  static const card = <BoxShadow>[
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  static const raised = <BoxShadow>[
    BoxShadow(
      color: Color(0x80000000),
      blurRadius: 36,
      offset: Offset(0, 16),
    ),
  ];

  static const button = <BoxShadow>[
    BoxShadow(
      color: Color(0x59E11D28),
      blurRadius: 22,
      offset: Offset(0, 10),
    ),
  ];
}

abstract final class AppDuration {
  static const fast = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 560);
}

/// iOS uses SF Pro automatically when [fontFamily] is null, which keeps the app
/// feeling native and avoids shipping/downloading a webfont.
abstract final class AppTypography {
  static const _family = null;

  static const display = TextStyle(
    fontFamily: _family,
    fontSize: 34,
    height: 1.15,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    color: AppColors.ink,
  );

  static const title = TextStyle(
    fontFamily: _family,
    fontSize: 26,
    height: 1.22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );

  static const headline = TextStyle(
    fontFamily: _family,
    fontSize: 20,
    height: 1.28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  static const body = TextStyle(
    fontFamily: _family,
    fontSize: 17,
    height: 1.45,
    fontWeight: FontWeight.w500,
    color: AppColors.inkSoft,
  );

  static const bodyStrong = TextStyle(
    fontFamily: _family,
    fontSize: 17,
    height: 1.4,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static const label = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppColors.inkSoft,
  );

  static const caption = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: AppColors.inkMuted,
  );

  static const button = TextStyle(
    fontFamily: _family,
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: Colors.white,
  );
}

abstract final class AppTheme {
  /// The app ships a single dark, black + red theme.
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.primaryBright,
        onSecondary: AppColors.onPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        error: AppColors.danger,
        onError: AppColors.onPrimary,
        outline: AppColors.hairline,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.lavender,
      canvasColor: AppColors.lavender,
      dividerColor: AppColors.hairline,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      iconTheme: const IconThemeData(color: AppColors.ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: AppColors.primary,
      ),
    );
  }

  /// Retained so older call sites keep working; the app is dark-only.
  static ThemeData get light => dark;

  /// Kept for call sites that predate the dark theme. The app is black, so this
  /// now renders light icons exactly like [systemOverlayLight].
  static const systemOverlayDark = systemOverlayLight;

  static const systemOverlayLight = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  );
}
