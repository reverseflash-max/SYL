import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Night watch": the whole app is a night drawing in, indigo ground and
/// bubbles in jewel tones coloured by type. The older light "Bento" palette is
/// kept for reference, but the app always shows the night. Colour names are
/// shared by both (butter is sapphire at night), so screens never check.
class Syl {
  /// Set by the app from the reader's choice; every colour below follows it.
  static bool dark = true;
  static _Palette get _p => dark ? _Palette.night : _Palette.day;

  static Color get paper => _p.paper;
  static Color get ink => _p.ink;
  static Color get muted => _p.muted;
  static Color get line => _p.line;
  static Color get white => _p.surface;
  static Color get inkSoft => _p.inkSoft;
  static Color get onInkMuted => _p.onInkMuted;

  /// The black bubble (reading card, lore, the tab bar) and its text.
  static Color get inverse => _p.inverse;
  static Color get onInverse => _p.onInverse;

  static Color get butter => _p.butter;
  static Color get mint => _p.mint;
  static Color get peach => _p.peach;
  static Color get lilac => _p.lilac;
  static Color get sky => _p.sky;
  static List<Color> get pastels => [butter, mint, peach, lilac, sky];

  /// The yellow of the + button and the chapter pill, in both modes.
  static const accent = Color(0xFFF5DC7A);
  static const onAccent = Color(0xFF171614);

  static Color get danger => dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E);

  /// Each type has its own bubble colour, everywhere it appears.
  static Color typeColor(String type) => switch (type) {
        'Character' => butter,
        'Location' => mint,
        'Item' => lilac,
        'Lore' => peach,
        _ => sky,
      };

  /// Dot colour for each type (filter chips, labels): dark enough to read on
  /// white and the pastels, light enough on night and the jewels.
  static Color typeDot(String type) => dark
      ? switch (type) {
          'Character' => const Color(0xFFF2C14E),
          'Location' => const Color(0xFF6FD39A),
          'Item' => const Color(0xFFB9A3F0),
          'Lore' => const Color(0xFFF59A6B),
          _ => muted,
        }
      : switch (type) {
          'Character' => const Color(0xFF8C6400),
          'Location' => const Color(0xFF2F7A47),
          'Item' => const Color(0xFF6650C2),
          'Lore' => const Color(0xFFB4541F),
          _ => muted,
        };

  /// Kept for anything without a type: the same colour for the same id.
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

  /// Libre Caslon Text, for book titles and index names.
  static TextStyle serif(BuildContext context,
          {double? fontSize, FontWeight? fontWeight, FontStyle? fontStyle, Color? color, double? height, double? letterSpacing}) =>
      Theme.of(context).extension<SylSerif>()!.style(
          fontSize: fontSize, fontWeight: fontWeight, fontStyle: fontStyle, color: color, height: height, letterSpacing: letterSpacing);

  /// The app theme for one mode. Builds from that mode's palette whatever
  /// mode is showing, so the light and dark themes can be made side by side.
  static ThemeData theme({bool googleFonts = true, bool dark = true}) {
    final was = Syl.dark;
    Syl.dark = dark;
    try {
      return _theme(googleFonts, dark);
    } finally {
      Syl.dark = was;
    }
  }

  static ThemeData _theme(bool googleFonts, bool dark) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: dark ? Brightness.dark : Brightness.light,
        surface: paper,
        onSurface: ink,
        primary: ink,
        onPrimary: paper,
        secondary: accent,
        onSecondary: onAccent,
        error: danger,
      ),
      scaffoldBackgroundColor: paper,
    );
    final text = (googleFonts ? GoogleFonts.bricolageGrotesqueTextTheme(base.textTheme) : base.textTheme)
        .apply(bodyColor: ink, displayColor: ink);
    return base.copyWith(
      extensions: [SylSerif(googleFonts: googleFonts)],
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 0.95),
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(backgroundColor: paper, foregroundColor: ink, elevation: 0, scrolledUnderElevation: 0),
      // Filled fields with the label floating INSIDE the box (an outline border
      // would park the label on the edge, over the field above it).
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: white,
        contentPadding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
        border: const UnderlineInputBorder(borderRadius: r14, borderSide: BorderSide.none),
        enabledBorder: const UnderlineInputBorder(borderRadius: r14, borderSide: BorderSide.none),
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
          // From the text theme, so button labels use the app's font, not the phone's.
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(44, 44),
          side: BorderSide(color: line, width: 1.5),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: ink)),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: inverse,
        contentTextStyle: text.bodyMedium?.copyWith(color: onInverse),
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
        // float above the pill navigation bar
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: paper,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(backgroundColor: paper),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: ink),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: DuskTransitions(),
        TargetPlatform.iOS: DuskTransitions(),
        TargetPlatform.windows: DuskTransitions(),
        TargetPlatform.macOS: DuskTransitions(),
        TargetPlatform.linux: DuskTransitions(),
      }),
    );
  }
}

/// Screens open like dusk falling: a soft fade with a slight rise, instead of
/// Android's stock zoom.
class DuskTransitions extends PageTransitionsBuilder {
  const DuskTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curve),
        child: child,
      ),
    );
  }
}

class _Palette {
  const _Palette({
    required this.paper, required this.ink, required this.muted, required this.line, required this.surface,
    required this.inkSoft, required this.onInkMuted, required this.inverse, required this.onInverse,
    required this.butter, required this.mint, required this.peach, required this.lilac, required this.sky,
  });
  final Color paper, ink, muted, line, surface, inkSoft, onInkMuted, inverse, onInverse;
  final Color butter, mint, peach, lilac, sky;

  static const day = _Palette(
    paper: Color(0xFFF3EFE7), ink: Color(0xFF171614), muted: Color(0xFF5F5A52), line: Color(0xFFCFC8BA),
    surface: Color(0xFFFFFFFF), inkSoft: Color(0xFF34322E), onInkMuted: Color(0xFFB9B3A8),
    inverse: Color(0xFF171614), onInverse: Color(0xFFF3EFE7),
    butter: Color(0xFFF5DC7A), mint: Color(0xFFBCE2C6), peach: Color(0xFFF7C4A0), lilac: Color(0xFFD5C8F4), sky: Color(0xFFC3DDF2),
  );

  // Jewel tones: sapphire, emerald, garnet, amethyst, slate.
  static const night = _Palette(
    paper: Color(0xFF1B2240), ink: Color(0xFFF2EEE6), muted: Color(0xFFA9B0CC), line: Color(0xFF3A4270),
    surface: Color(0xFF262E52), inkSoft: Color(0xFFC9CEE2), onInkMuted: Color(0xFFA9B0CC),
    inverse: Color(0xFF121830), onInverse: Color(0xFFF2EEE6),
    butter: Color(0xFF34509A), mint: Color(0xFF235A43), peach: Color(0xFF74293A), lilac: Color(0xFF55387E), sky: Color(0xFF34405A),
  );
}

/// The serif face. google_fonts picks the file by weight and style, so each
/// variant is asked for by name rather than by copying one style.
class SylSerif extends ThemeExtension<SylSerif> {
  const SylSerif({this.googleFonts = true});
  final bool googleFonts;

  TextStyle style({double? fontSize, FontWeight? fontWeight, FontStyle? fontStyle, Color? color, double? height, double? letterSpacing}) =>
      googleFonts
          ? GoogleFonts.libreCaslonText(
              fontSize: fontSize, fontWeight: fontWeight, fontStyle: fontStyle, color: color, height: height, letterSpacing: letterSpacing)
          : TextStyle(
              fontFamily: 'Libre Caslon Text',
              fontSize: fontSize, fontWeight: fontWeight, fontStyle: fontStyle, color: color, height: height, letterSpacing: letterSpacing);

  @override
  SylSerif copyWith({bool? googleFonts}) => SylSerif(googleFonts: googleFonts ?? this.googleFonts);

  @override
  SylSerif lerp(SylSerif? other, double t) => this;
}
