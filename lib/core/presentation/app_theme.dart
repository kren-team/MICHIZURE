import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 墨（ink）と朱（vermilion）の2色を軸にしたカラーシステム。
///
/// 主要操作は紙色（[paper]）の面に墨文字、負債・回数・進捗だけに朱（[accent]）を使う。
/// 色数を絞り、グラデーションと枠線の多用を避ける。
abstract final class MichizureColors {
  static const background = Color(0xFF0D0D0F);
  static const surface = Color(0xFF17171A);
  static const elevatedSurface = Color(0xFF222226);
  static const border = Color(0xFF2C2C31);
  static const paper = Color(0xFFF2EEE6);
  static const onPaper = Color(0xFF141416);
  static const accent = Color(0xFFFF5B2E);
  static const onAccent = Color(0xFF1A0904);
  static const textPrimary = Color(0xFFF2EEE6);
  static const textSecondary = Color(0xFF9A968E);
  static const textTertiary = Color(0xFF66635E);
  static const success = Color(0xFF45C98F);
  static const warning = Color(0xFFF2B13D);
  static const error = Color(0xFFFF6B6B);
}

abstract final class MichizureSpacing {
  static const page = 20.0;
  static const card = 20.0;
  static const section = 28.0;
  static const item = 12.0;
}

abstract final class MichizureRadii {
  static const card = 18.0;
  static const control = 14.0;
  static const pill = 999.0;
}

abstract final class MichizureTextStyles {
  /// 回数や残り時間など、桁が揃っていてほしい大きな数値。
  static const counter = TextStyle(
    fontSize: 56,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.5,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// セクション見出し。本文より小さく、色で階層を示す。
  static const overline = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: MichizureColors.textSecondary,
  );
}

ThemeData buildMichizureTheme() {
  const scheme = ColorScheme.dark(
    primary: MichizureColors.paper,
    onPrimary: MichizureColors.onPaper,
    secondary: MichizureColors.accent,
    onSecondary: MichizureColors.onAccent,
    error: MichizureColors.error,
    onError: Color(0xFF2B0707),
    surface: MichizureColors.surface,
    onSurface: MichizureColors.textPrimary,
    surfaceContainerHighest: MichizureColors.elevatedSurface,
    outline: MichizureColors.border,
    outlineVariant: MichizureColors.border,
  );
  final base = ThemeData(
    colorScheme: scheme,
    brightness: Brightness.dark,
    useMaterial3: true,
  );
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(MichizureRadii.control),
    borderSide: BorderSide.none,
  );

  return base.copyWith(
    scaffoldBackgroundColor: MichizureColors.background,
    canvasColor: MichizureColors.background,
    dividerColor: MichizureColors.border,
    splashColor: MichizureColors.paper.withValues(alpha: 0.06),
    highlightColor: MichizureColors.paper.withValues(alpha: 0.04),
    textTheme: base.textTheme
        .apply(
          bodyColor: MichizureColors.textPrimary,
          displayColor: MichizureColors.textPrimary,
        )
        .copyWith(
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            color: MichizureColors.textSecondary,
            height: 1.5,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            color: MichizureColors.textSecondary,
            height: 1.4,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: MichizureColors.background,
      foregroundColor: MichizureColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        color: MichizureColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: MichizureColors.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MichizureRadii.card),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MichizureColors.surface,
      labelStyle: const TextStyle(color: MichizureColors.textSecondary),
      hintStyle: const TextStyle(color: MichizureColors.textTertiary),
      helperStyle: const TextStyle(color: MichizureColors.textSecondary),
      prefixIconColor: MichizureColors.textSecondary,
      suffixIconColor: MichizureColors.textSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(color: MichizureColors.paper, width: 1.2),
      ),
      errorBorder: outline.copyWith(
        borderSide: const BorderSide(color: MichizureColors.error),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: const BorderSide(color: MichizureColors.error, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 54),
        backgroundColor: MichizureColors.paper,
        foregroundColor: MichizureColors.onPaper,
        disabledBackgroundColor: MichizureColors.elevatedSurface,
        disabledForegroundColor: MichizureColors.textTertiary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MichizureRadii.control),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 54),
        backgroundColor: MichizureColors.surface,
        foregroundColor: MichizureColors.textPrimary,
        disabledForegroundColor: MichizureColors.textTertiary,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MichizureRadii.control),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: MichizureColors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MichizureRadii.control),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: MichizureColors.textSecondary,
        minimumSize: const Size.square(48),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: MichizureColors.textTertiary, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? MichizureColors.accent
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(MichizureColors.onAccent),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? MichizureColors.onAccent
            : MichizureColors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? MichizureColors.accent
            : MichizureColors.elevatedSurface,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: MichizureColors.textSecondary,
      textColor: MichizureColors.textPrimary,
      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    ),
    dividerTheme: const DividerThemeData(
      color: MichizureColors.border,
      thickness: 1,
      space: 32,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: MichizureColors.elevatedSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MichizureRadii.card),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: MichizureColors.elevatedSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MichizureRadii.control),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MichizureColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: MichizureColors.textTertiary,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MichizureColors.paper,
      contentTextStyle: const TextStyle(
        color: MichizureColors.onPaper,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MichizureRadii.control),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MichizureColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: MichizureColors.accent.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? MichizureColors.accent
              : MichizureColors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? MichizureColors.textPrimary
              : MichizureColors.textSecondary,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MichizureColors.accent,
      linearTrackColor: MichizureColors.elevatedSurface,
      circularTrackColor: MichizureColors.elevatedSurface,
    ),
  );
}
