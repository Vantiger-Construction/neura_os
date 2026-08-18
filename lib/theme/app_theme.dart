import 'package:flutter/material.dart';

/// Centralized theme for Neura.
///
/// Replaces the previous bare `ThemeData.dark()`, whose Material 3 tonal
/// palette leans on muted grayish-purple surfaces and low-contrast
/// `onSurfaceVariant` text — the root cause of the app looking washed out
/// and hard to read. This defines an explicit, high-contrast dark palette
/// (and a matching light palette for the `ThemeScreen` toggle) plus a
/// `highContrast` variant that pushes text/outlines further for users who
/// enable it in Settings.
class AppTheme {
  AppTheme._();

  // Matches the floating mascot window's own backdrop color, so the shell
  // and the rest of the app read as one consistent surface.
  static const _darkBg = Color(0xFF0D0D14);
  static const _darkSurface = Color(0xFF1A1A24);
  static const _accent = Color(0xFFFFC94D);

  static ThemeData dark({bool highContrast = false}) {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _accent,
      onPrimary: const Color(0xFF1A1200),
      secondary: _accent,
      onSecondary: const Color(0xFF1A1200),
      surface: highContrast ? const Color(0xFF1E1E29) : _darkSurface,
      onSurface: highContrast ? Colors.white : const Color(0xFFF5F5F7),
      surfaceContainerHighest:
          highContrast ? const Color(0xFF2A2A38) : const Color(0xFF232330),
      onSurfaceVariant:
          highContrast ? const Color(0xFFE8E8EE) : const Color(0xFFC9C9D4),
      outline: highContrast ? const Color(0xFF9A9AA8) : const Color(0xFF5A5A68),
      outlineVariant:
          highContrast ? const Color(0xFF6E6E7C) : const Color(0xFF3A3A46),
      error: const Color(0xFFFF6B6B),
      onError: const Color(0xFF2B0000),
    );

    return _themeFrom(colorScheme, _darkBg);
  }

  static ThemeData light({bool highContrast = false}) {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: const Color(0xFF8A5A00),
      onPrimary: Colors.white,
      secondary: const Color(0xFF8A5A00),
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: highContrast ? Colors.black : const Color(0xFF1A1A1F),
      surfaceContainerHighest: const Color(0xFFEDEDF2),
      onSurfaceVariant:
          highContrast ? const Color(0xFF1A1A1F) : const Color(0xFF44444C),
      outline: highContrast ? const Color(0xFF44444C) : const Color(0xFF8E8E96),
      outlineVariant:
          highContrast ? const Color(0xFF6A6A72) : const Color(0xFFC7C7CE),
      error: const Color(0xFFB3261E),
      onError: Colors.white,
    );

    return _themeFrom(colorScheme, const Color(0xFFF7F7FA));
  }

  static ThemeData _themeFrom(ColorScheme colorScheme, Color background) {
    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);
    final textTheme = base.textTheme.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
      decorationColor: colorScheme.onSurface,
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface),
      cardTheme: base.cardTheme.copyWith(
        color: colorScheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        textColor: colorScheme.onSurface,
        iconColor: colorScheme.onSurface,
        subtitleTextStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
