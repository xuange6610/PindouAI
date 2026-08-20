import 'package:flutter/material.dart';

abstract final class AppColors {
  static const coral = Color(0xFFE96354);
  static const coralDark = Color(0xFFC9473B);
  static const teal = Color(0xFF287D75);
  static const ink = Color(0xFF2D2A2A);
  static const muted = Color(0xFF77706D);
  static const canvas = Color(0xFFFFF9F4);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFF0E5DD);
  static const mint = Color(0xFFE5F4F0);
  static const peach = Color(0xFFFFE7DE);
}

abstract final class AppTheme {
  static ThemeData get light => lightWith(AppColors.coral);

  /// Keeps a user-selected hue while moving very light colors to a tone that
  /// remains readable with white labels. Raw RGB colors such as pale cyan or
  /// yellow used to make buttons and the home creation card look blank.
  static Color accessibleAccent(Color accent) {
    final opaque = Color.fromARGB(
      255,
      (accent.toARGB32() >> 16) & 0xFF,
      (accent.toARGB32() >> 8) & 0xFF,
      accent.toARGB32() & 0xFF,
    );
    if (_contrastRatio(opaque, Colors.white) >= 4.5) return opaque;
    for (var step = 1; step <= 20; step++) {
      final candidate = Color.lerp(opaque, Colors.black, step / 20)!;
      if (_contrastRatio(candidate, Colors.white) >= 4.5) return candidate;
    }
    return AppColors.ink;
  }

  static double _contrastRatio(Color first, Color second) {
    final firstLuminance = first.computeLuminance();
    final secondLuminance = second.computeLuminance();
    final lighter = firstLuminance > secondLuminance
        ? firstLuminance
        : secondLuminance;
    final darker = firstLuminance > secondLuminance
        ? secondLuminance
        : firstLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static ThemeData lightWith(Color accent) {
    final accentDark = accessibleAccent(accent);
    final canvas = Color.lerp(Colors.white, accent, 0.045)!;
    final soft = Color.lerp(Colors.white, accent, 0.15)!;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
          primary: accentDark,
          secondary: AppColors.teal,
          surface: AppColors.card,
        ).copyWith(
          onPrimary: Colors.white,
          primaryContainer: soft,
          onPrimaryContainer: accentDark,
          onSecondary: Colors.white,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      // Bundle the Chinese font instead of relying on vendor-specific Android
      // font names. Some devices do not expose the named system families and
      // render CJK text as unreadable replacement glyphs.
      fontFamily: 'NotoSansSC',
      fontFamilyFallback: const [
        'Noto Sans CJK SC',
        'Microsoft YaHei',
        'sans-serif',
      ],
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.ink,
          fontSize: 31,
          fontWeight: FontWeight.w800,
          height: 1.18,
        ),
        headlineSmall: TextStyle(
          color: AppColors.ink,
          fontSize: 21,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(color: AppColors.ink, height: 1.45),
        bodySmall: TextStyle(color: AppColors.muted, height: 1.4),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.card,
        selectedColor: soft,
        disabledColor: const Color(0xFFF2EFEC),
        checkmarkColor: accentDark,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AppColors.coralDark,
          fontWeight: FontWeight.w800,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentDark,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentDark,
          side: BorderSide(color: accent),
          minimumSize: const Size(56, 46),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.ink),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accentDark,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.card,
        indicatorColor: soft,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accentDark
                : AppColors.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.ink
                : AppColors.muted,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accentDark : Colors.white,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: AppColors.muted, width: 1.5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: AppColors.line,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.line),
        ),
      ),
    );
  }
}
