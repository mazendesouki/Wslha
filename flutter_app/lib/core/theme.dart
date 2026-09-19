import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Teal-tinted card/list-row background — replaces plain white on list
  /// items across the customer app. Went through two lighter attempts
  /// (0xFFEEF5F4, then 0xFFD9EAE7) that still read as "too faint" —
  /// explicitly asked for a dark, unmistakable tint, so this is a clearly
  /// saturated mid-teal rather than a subtle background wash. Text on top
  /// stays dark (near-black/primary), which still reads fine at this
  /// saturation.
  static const cardTint = Color(0xFFAAD2CA);
}

// Soft off-white used by the "modern" theme variant's backgrounds/fills —
// matches the tint already used elsewhere in the app (e.g. invoice PDF's
// _pdfLightBg) so the refreshed look still reads as the same brand.
const _modernSurfaceTint = Color(0xFFF7FAF9);
const _modernBorder = Color(0xFFE5E7EB);

// Dark-mode surfaces — a near-black teal tint (not flat grey) so the brand
// color still reads as "the same app", just inverted, matching the
// established pattern of keeping AppColors.primary constant across variants
// rather than defining a whole second brand palette.
const _darkScaffoldBg = Color(0xFF0E1513);
const _darkSurface = Color(0xFF16211E);

/// [modern] is a safe, screen-layout-untouched visual refresh (rounder
/// corners, softer surface tint, bolder type) — trialled on the customer
/// app only (see app.dart) before considering it for driver/merchant, so it
/// stays an opt-in flag rather than replacing the existing theme outright.
///
/// [dark] drives Scaffold/AppBar/inputs/cards/dialogs/nav bars — every
/// Material-theme-driven surface. It does NOT retint screens that paint
/// their own hardcoded `Colors.white`/hex containers directly instead of
/// reading Theme.of(context) (a lot of this app's custom cards do) — those
/// stay light until each screen is individually converted in a follow-up
/// pass. ThemeController below is what actually switches this on.
ThemeData buildAppTheme({bool modern = false, bool dark = false}) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      error: AppColors.error,
      surface: dark ? _darkSurface : Colors.white,
    ),
    scaffoldBackgroundColor: dark ? _darkScaffoldBg : (modern ? _modernSurfaceTint : Colors.white),
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
      backgroundColor: dark ? _darkSurface : (modern ? AppColors.primary : Colors.white),
      foregroundColor: dark || modern ? Colors.white : Colors.black,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        color: dark || modern ? Colors.white : null,
      ),
      iconTheme: IconThemeData(color: dark || modern ? Colors.white : Colors.black),
      actionsIconTheme: IconThemeData(color: dark || modern ? Colors.white : Colors.black),
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
    cardTheme: modern || dark
        ? CardThemeData(
            elevation: 0,
            color: dark ? _darkSurface : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: modern ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)) : null,
            margin: EdgeInsets.zero,
          )
        : null,
    chipTheme: modern
        ? ChipThemeData(
            backgroundColor: dark ? AppColors.primary.withValues(alpha: 0.25) : AppColors.primaryLight,
            labelStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: dark ? Colors.white : AppColors.primaryDark),
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
      fillColor: dark ? _darkSurface : (modern ? _modernSurfaceTint : Colors.white),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: modern || dark ? BorderSide.none : const BorderSide(color: _modernBorder, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: modern || dark ? BorderSide.none : const BorderSide(color: _modernBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      // The default label color (a light grey meant for a white background)
      // was nearly unreadable floating above a field sitting on the new
      // teal cardTint — "العناوين محتاجة تظبيط". Color-only fix — the first
      // attempt also bumped fontWeight, which made the inline (unfloated,
      // full-size) label render heavier/wider and crowd into the field box
      // ("العناوين متداخلة على الخانات"). Same size/weight as Material's
      // default, just a darker color.
      labelStyle: modern ? const TextStyle(color: AppColors.primaryDark) : null,
      floatingLabelStyle: modern ? const TextStyle(color: AppColors.primaryDark) : null,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: dark ? _darkSurface : Colors.white,
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
            backgroundColor: dark ? _darkSurface : Colors.white,
            elevation: 8,
            indicatorColor: dark ? AppColors.primary.withValues(alpha: 0.35) : AppColors.primaryLight,
            indicatorShape: const StadiumBorder(),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                color: selected ? (dark ? Colors.white : AppColors.primaryDark) : AppColors.textFaint,
              );
            }),
          )
        : null,
  );
}

/// Screens across this app mostly paint their own cards/borders with
/// hardcoded `Colors.white`/hex literals instead of reading Theme.of —
/// buildAppTheme()'s `dark` flag alone doesn't reach any of that. This
/// extension is the per-screen retrofit vocabulary: swap a hardcoded
/// `Colors.white` card fill for `context.surfaceColor`, a hardcoded
/// `Color(0xFFE9ECEB)` border for `context.borderColor`, etc., screen by
/// screen. Not every screen has been converted yet — this only helps once a
/// screen actually uses it.
extension AppThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Card/sheet/dialog fill — was `Colors.white` almost everywhere.
  Color get surfaceColor => isDark ? _darkSurface : Colors.white;

  /// Thin 1-1.5px hairline borders — was `Color(0xFFE9ECEB)` almost everywhere.
  Color get borderColor => isDark ? const Color(0xFF2A3532) : const Color(0xFFE9ECEB);

  /// Soft tinted page background — was `Color(0xFFF7FAF9)` almost everywhere.
  Color get mutedSurface => isDark ? _darkScaffoldBg : const Color(0xFFF7FAF9);

  /// Primary body text — was implicit black/`Colors.black87` almost everywhere.
  Color get bodyText => isDark ? Colors.white : Colors.black87;
}

/// Persists and broadcasts the user's dark-mode choice (light/dark/system)
/// — a plain ValueNotifier<ThemeMode> app.dart's MaterialApp listens to via
/// ValueListenableBuilder, same shared_preferences-backed pattern
/// settings_screen.dart already uses for the notifications toggle. Whether
/// the toggle even shows is separately gated by
/// FeatureFlags.darkModeEnabled (admin-controlled); this class only tracks
/// the user's own choice once it's available.
class ThemeController {
  ThemeController._();
  static const _key = 'wslha_theme_mode';

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      mode.value = switch (saved) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // Keep the ThemeMode.system default on any prefs failure.
    }
  }

  static Future<void> set(ThemeMode value) async {
    mode.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.name);
    } catch (_) {
      // The in-memory value is already updated — a failed persist just
      // means the choice won't survive a cold restart, not a crash.
    }
  }
}
