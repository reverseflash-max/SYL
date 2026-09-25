import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Bento" look: warm paper background, ink-black accents, pastel note cards,
/// big bold Bricolage Grotesque headings.
class Syl {
  static const paper = Color(0xFFF3EFE7);
  static const ink = Color(0xFF171614);
  static const muted = Color(0xFF5F5A52);
  static const line = Color(0xFFCFC8BA);
  static const white = Color(0xFFFFFFFF);
  static const inkSoft = Color(0xFF34322E);
  static const onInkMuted = Color(0xFFB9B3A8);

  static const butter = Color(0xFFF5DC7A);
  static const mint = Color(0xFFBCE2C6);
  static const peach = Color(0xFFF7C4A0);
  static const lilac = Color(0xFFD5C8F4);
  static const sky = Color(0xFFC3DDF2);
  static const pastels = [butter, mint, peach, lilac, sky];

  static const danger = Color(0xFFB3261E);

  /// Dot colour for each type (filter chips, labels).
  static Color typeDot(String type) => switch (type) {
        'Character' => const Color(0xFFE8B93A),
        'Location' => const Color(0xFF57A86F),
        'Item' => const Color(0xFF8C74D6),
        'Lore' => const Color(0xFFE38A55),
        _ => muted,
      };

  /// Each entity keeps the same pastel wherever it appears.
  static Color cardColor(String id) {
    var h = 0;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return pastels[h % pastels.length];
  }

  static const r24 = BorderRadius.all(Radius.circular(24));
  static const r20 = BorderRadius.all(Radius.circular(20));
  static const r14 = BorderRadius.all(Radius.circular(14));

  static ThemeData theme({bool googleFonts = true}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: butter,
        brightness: Brightness.light,
        surface: paper,
        onSurface: ink,
        primary: ink,
        onPrimary: paper,
        secondary: butter,
        onSecondary: ink,
        error: danger,
      ),
      scaffoldBackgroundColor: paper,
    );
    final text = (googleFonts ? GoogleFonts.bricolageGrotesqueTextTheme(base.textTheme) : base.textTheme)
        .apply(bodyColor: ink, displayColor: ink);
    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 0.95),
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: paper, foregroundColor: ink, elevation: 0, scrolledUnderElevation: 0),
      // Filled fields with the label floating INSIDE the box (an outline border
      // would park the label on the edge, over the field above it).
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: white,
        contentPadding: EdgeInsets.fromLTRB(16, 22, 16, 12),
        border: UnderlineInputBorder(borderRadius: r14, borderSide: BorderSide.none),
        enabledBorder: UnderlineInputBorder(borderRadius: r14, borderSide: BorderSide.none),
        focusedBorder: UnderlineInputBorder(borderRadius: r14, borderSide: BorderSide(color: ink, width: 2)),
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        floatingLabelStyle: TextStyle(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: paper,
          minimumSize: const Size(44, 48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(44, 44),
          side: const BorderSide(color: line, width: 1.5),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: ink)),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: paper),
        behavior: SnackBarBehavior.floating,
        shape: StadiumBorder(),
        // float above the pill navigation bar
        insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 100),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: paper,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: paper),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: ink),
    );
  }
}
