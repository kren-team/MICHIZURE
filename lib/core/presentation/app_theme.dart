import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class MichizureColors {
  static const background = Color(0xFF05091A);
  static const surface = Color(0xFF10182E);
  static const elevatedSurface = Color(0xFF18213B);
  static const border = Color(0xFF2A3555);
  static const purple = Color(0xFFB99AFF);
  static const pink = Color(0xFFF184B5);
  static const textPrimary = Color(0xFFF7F6FF);
  static const textSecondary = Color(0xFFA8B0C8);
  static const success = Color(0xFF68D6B3);
  static const warning = Color(0xFFF2BF75);
  static const error = Color(0xFFFF7F9F);
}

abstract final class MichizureGradients {
  static const primary = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [MichizureColors.purple, MichizureColors.pink],
  );

  static const subtle = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1C2546), MichizureColors.surface],
  );
}

abstract final class MichizureSpacing {
  static const page = 20.0;
  static const card = 18.0;
  static const section = 24.0;
  static const item = 12.0;
}

abstract final class MichizureRadii {
  static const card = 20.0;
  static const control = 16.0;
  static const pill = 999.0;
}

ThemeData buildMichizureTheme() {
  const scheme = ColorScheme.dark(
    primary: MichizureColors.purple,
    onPrimary: Color(0xFF161026),
    secondary: MichizureColors.pink,
    onSecondary: Color(0xFF28101D),
    error: MichizureColors.error,
    onError: Color(0xFF2B0713),
    surface: MichizureColors.surface,
    onSurface: MichizureColors.textPrimary,
  );
  final base = ThemeData(
    colorScheme: scheme,
    brightness: Brightness.dark,
    useMaterial3: true,
  );
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(MichizureRadii.control),
    borderSide: const BorderSide(color: MichizureColors.border),
  );

  return base.copyWith(
    scaffoldBackgroundColor: MichizureColors.background,
    canvasColor: MichizureColors.background,
    dividerColor: MichizureColors.border,
    splashColor: MichizureColors.purple.withValues(alpha: 0.10),
    highlightColor: MichizureColors.purple.withValues(alpha: 0.06),
    textTheme: base.textTheme
        .apply(
          bodyColor: MichizureColors.textPrimary,
          displayColor: MichizureColors.textPrimary,
        )
        .copyWith(
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            color: MichizureColors.textSecondary,
            height: 1.45,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            color: MichizureColors.textSecondary,
            height: 1.4,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
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
        fontSize: 20,
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
        side: const BorderSide(color: MichizureColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MichizureColors.surface,
      labelStyle: const TextStyle(color: MichizureColors.textSecondary),
      hintStyle: const TextStyle(color: MichizureColors.textSecondary),
      helperStyle: const TextStyle(color: MichizureColors.textSecondary),
      prefixIconColor: MichizureColors.textSecondary,
      suffixIconColor: MichizureColors.textSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(color: MichizureColors.purple, width: 1.5),
      ),
      errorBorder: outline.copyWith(
        borderSide: const BorderSide(color: MichizureColors.error),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: const BorderSide(color: MichizureColors.error, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        backgroundColor: MichizureColors.purple,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: MichizureColors.elevatedSurface,
        disabledForegroundColor: MichizureColors.textSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MichizureRadii.control),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        backgroundColor: MichizureColors.surface,
        foregroundColor: MichizureColors.purple,
        side: const BorderSide(color: MichizureColors.purple),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MichizureRadii.control),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: MichizureColors.purple,
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
      side: const BorderSide(color: MichizureColors.border, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? MichizureColors.purple
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Color(0xFF161026)),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: MichizureColors.purple,
      textColor: MichizureColors.textPrimary,
      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
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
        side: const BorderSide(color: MichizureColors.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MichizureColors.elevatedSurface,
      contentTextStyle: const TextStyle(color: MichizureColors.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MichizureRadii.control),
        side: const BorderSide(color: MichizureColors.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MichizureColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: MichizureColors.pink.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? MichizureColors.pink
              : MichizureColors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? MichizureColors.pink
              : MichizureColors.textSecondary,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: MichizureColors.surface,
      selectedItemColor: MichizureColors.pink,
      unselectedItemColor: MichizureColors.textSecondary,
      type: BottomNavigationBarType.fixed,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MichizureColors.pink,
      linearTrackColor: MichizureColors.elevatedSurface,
      circularTrackColor: MichizureColors.elevatedSurface,
    ),
  );
}
