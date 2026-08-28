import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand palette lifted directly from the web app's public/global.css
/// (--color-primary / --color-primary-dark / --color-primary-light /
/// --color-accent), so the Flutter app reads as the same product.
class AppColors {
  static const primary = Color(0xFF0E4B49);
  static const primaryDark = Color(0xFF082F2E);
  static const primaryLight = Color(0xFFE3EDEC);
  static const accent = Color(0xFFB8863B);
  static const error = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);
  static const textFaint = Color(0xFF9CA3AF);

  /// Soft teal-tinted card/list-row background — replaces plain white on
  /// list items across the customer app so they read as shaded content
  /// against the page instead of blending into it (the page background is
  /// already a near-white tint, so a plain-white card barely stood out).
  static const cardTint = Color(0xFFEEF5F4);
}

// Soft off-white used by the "modern" theme variant's backgrounds/fills —
// matches the tint already used elsewhere in the app (e.g. invoice PDF's
// _pdfLightBg) so the refreshed look still reads as the same brand.
const _modernSurfaceTint = Color(0xFFF7FAF9);
const _modernBorder = Color(0xFFE5E7EB);

/// [modern] is a safe, screen-layout-untouched visual refresh (rounder
/// corners, softer surface tint, bolder type) — trialled on the customer
/// app only (see app.dart) before considering it for driver/merchant, so it
/// stays an opt-in flag rather than replacing the existing theme outright.
ThemeData buildAppTheme({bool modern = false}) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: modern ? _modernSurfaceTint : Colors.white,
  );

  // Cairo matches the web app's Arabic display font (see global.css
  // font-family stack); El Messiri is used there for headings, but Cairo
  // alone reads cleanly across all weights so we keep the font set to one
  // family for a simpler Flutter theme.
  final textTheme = GoogleFonts.cairoTextTheme(base.textTheme);

  final buttonRadius = modern ? 16.0 : 12.0;
  final fieldRadius = modern ? 14.0 : 10.0;
  final cardRadius = modern ? 18.0 : 12.0;

  return base.copyWith(
    textTheme: modern
        ? textTheme.copyWith(
            titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.2),
            titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          )
        : textTheme,
    appBarTheme: AppBarTheme(
      // A colored app bar is the single most visible "this looks different"
      // cue on nearly every screen — the earlier off-white-vs-white tint
      // was too close to read as a real change at a glance.
      backgroundColor: modern ? AppColors.primary : Colors.white,
      foregroundColor: modern ? Colors.white : Colors.black,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        color: modern ? Colors.white : null,
      ),
      iconTheme: IconThemeData(color: modern ? Colors.white : Colors.black),
      actionsIconTheme: IconThemeData(color: modern ? Colors.white : Colors.black),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: modern ? 0 : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
        textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
    ),
    outlinedButtonTheme: modern
        ? OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: _modernBorder, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
              textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          )
        : null,
    cardTheme: modern
        ? CardThemeData(
            elevation: 0,
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
            margin: EdgeInsets.zero,
          )
        : null,
    chipTheme: modern
        ? ChipThemeData(
            backgroundColor: AppColors.primaryLight,
            labelStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            side: BorderSide.none,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          )
        : null,
    snackBarTheme: modern
        ? SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          )
        : null,
    dialogTheme: modern ? DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))) : null,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: modern ? _modernSurfaceTint : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: modern ? BorderSide.none : const BorderSide(color: _modernBorder, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: modern ? BorderSide.none : const BorderSide(color: _modernBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textFaint,
      type: BottomNavigationBarType.fixed,
      elevation: modern ? 8 : null,
    ),
    // Only consumed where a screen opts into the Material 3 NavigationBar
    // widget instead of the classic BottomNavigationBar (currently just the
    // customer app's HomeShell) — the pill-shaped selected-tab indicator is
    // a much more recognizable "modern" cue than a themed classic bar.
    navigationBarTheme: modern
        ? NavigationBarThemeData(
            backgroundColor: Colors.white,
            elevation: 8,
            indicatorColor: AppColors.primaryLight,
            indicatorShape: const StadiumBorder(),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                color: selected ? AppColors.primaryDark : AppColors.textFaint,
              );
            }),
          )
        : null,
  );
}
