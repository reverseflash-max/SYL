// Design checks: every screen, on a normal and a small Android phone, must
//  - have tap targets of at least 48x48dp (Android guideline),
//  - label every tappable thing for screen readers,
//  - meet text contrast (4.5:1, or 3:1 for large text): the text's own colour
//    against the background measured in the rendered pixels (Flutter's
//    textContrastGuideline samples the wrong area inside the tab PageView),
//  - use no text smaller than 11sp,
//  - draw all text in a named font (text without one falls back to the
//    phone's system font; in tests it shows as solid blocks).
//
// Screenshots: set SYL_SHOTS to a folder to also save every screen as a PNG
// at the phone's real resolution, plus one contact sheet per phone:
//
//   SYL_SHOTS=/tmp/shots flutter test test/design/design_check_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/state/library_store.dart';
import 'package:mobile/theme/syl_theme.dart';
import 'package:mobile/ui/home_shell.dart';
import 'package:mobile/ui/new_entity_screen.dart';
import 'package:provider/provider.dart';

import 'sample_library.dart';

class Device {
  const Device(this.name, this.size, this.pixelRatio);
  final String name;
  final Size size; // logical pixels (dp)
  final double pixelRatio;
}

const devices = [
  Device('phone', Size(412, 915), 2.625), // Pixel 8 class
  Device('small', Size(360, 640), 2.0), // small Android phone
];

class Scenario {
  const Scenario(this.name, this.open, {this.store = sampleLibrary});
  final String name;
  final Future<void> Function(WidgetTester tester) open;
  final LibraryStore Function() store;
}

Future<void> _tapNav(WidgetTester t, IconData icon) async {
  await t.tap(find.byIcon(icon));
  await t.pumpAndSettle();
}

final scenarios = <Scenario>[
  Scenario('1-library', (t) async {}),
  Scenario('2-entry', (t) async {
    await t.tap(find.text('Aragorn').first);
    await t.pumpAndSettle();
  }),
  Scenario('3-map', (t) => _tapNav(t, Icons.hub_outlined)),
  Scenario('4-books', (t) => _tapNav(t, Icons.menu_book_outlined)),
  Scenario('5-quick-add', (t) async {
    await t.tap(find.byTooltip('Add'));
    await t.pumpAndSettle();
    await t.tap(find.text('New fact'));
    await t.pumpAndSettle();
  }),
  Scenario('6-new-entry', (t) async {
    await t.scrollUntilVisible(find.text('+ New entry'), 200, scrollable: find.byType(Scrollable).first);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -400)); // clear of the floating bar
    await t.pumpAndSettle();
    await t.tap(find.text('+ New entry'));
    await t.pumpAndSettle();
    expect(find.byType(NewEntityScreen), findsOneWidget);
  }),
  Scenario('7-empty-library', (t) async {}, store: LibraryStore.memory),
  Scenario('8-settings', (t) => _tapNav(t, Icons.tune)),
  Scenario('9-add-menu', (t) async {
    await t.tap(find.byTooltip('Add'));
    await t.pumpAndSettle();
  }),
  Scenario('10-new-book', (t) async {
    await t.tap(find.byTooltip('Add'));
    await t.pumpAndSettle();
    await t.tap(find.text('New book'));
    await t.pumpAndSettle();
  }),
  Scenario('11-book-sheet', (t) async {
    await _tapNav(t, Icons.menu_book_outlined);
    await t.tap(find.text('Mistborn: The Final Empire'));
    await t.pumpAndSettle();
  }),
];

/// Text below this size (in logical pixels, before the user's text scaling) fails.
const double minTextSize = 11;

/// Flutter's bundled fonts, for icons and the contact sheet captions.
String get _materialFonts {
  var dir = File(Platform.resolvedExecutable).parent;
  while (!Directory('${dir.path}/bin/cache/artifacts/material_fonts').existsSync() && dir.parent.path != dir.path) {
    dir = dir.parent;
  }
  return '${dir.path}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files.where((f) => File(f).existsSync())) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

/// Visible text with no font family: it would render in the phone's system font.
List<String> _noFont(WidgetTester tester, Size screen) {
  final out = <String>{};
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.attached && o.hasSize) {
      final box = MatrixUtils.transformRect(o.getTransformTo(null), Offset.zero & o.size);
      final text = o.text.toPlainText().trim();
      if (box.overlaps(Offset.zero & screen) && text.isNotEmpty && o.text.style?.fontFamily == null) {
        out.add('"${text.length > 30 ? '${text.substring(0, 30)}…' : text}"');
      }
    }
    o.visitChildren(visit);
  }

  visit(tester.binding.rootElement!.renderObject!);
  return out.toList();
}

List<String> _smallText(WidgetTester tester, Size screen) {
  final out = <String>{};
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.attached && o.hasSize) {
      final box = MatrixUtils.transformRect(o.getTransformTo(null), Offset.zero & o.size);
      if (box.overlaps(Offset.zero & screen)) {
        o.text.visitChildren((span) {
          final size = span.style?.fontSize;
          if (size != null && size < minTextSize && span is TextSpan && (span.text?.trim().isNotEmpty ?? false)) {
            out.add('"${span.text!.trim()}" is ${size}sp');
          }
          return true;
        });
      }
    }
    o.visitChildren(visit);
  }

  visit(tester.binding.rootElement!.renderObject!);
  return out.toList();
}

double _luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Whether all of [paragraph] is what the user sees in [box]: not covered by
/// another screen, a sheet's barrier or the floating bar (text scrolled under
/// the bar is a scroll position, not a design fault).
bool _onTop(WidgetTester tester, RenderParagraph paragraph, Rect box) {
  final inner = box.deflate(1);
  for (final point in [inner.center, inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight]) {
    final hits = HitTestResult();
    tester.binding.hitTestInView(hits, point, tester.view.viewId);
    if (!hits.path.any((entry) => entry.target == paragraph)) return false;
  }
  return true;
}

/// Every visible text whose colour is too close to the background behind it.
/// The background is the most common colour in the text's box on the screenshot.
List<String> _lowContrast(WidgetTester tester, ui.Image shot, ByteData pixels, Size screen, double dpr) {
  final out = <String>{};
  Color pixel(int x, int y) {
    final i = (y * shot.width + x) * 4;
    return Color.fromARGB(255, pixels.getUint8(i), pixels.getUint8(i + 1), pixels.getUint8(i + 2));
  }

  void visit(RenderObject o) {
    if (o is RenderParagraph && o.attached && o.hasSize && o.size.width > 0) {
      final full = MatrixUtils.transformRect(o.getTransformTo(null), Offset.zero & o.size);
      final box = full.intersect(Offset.zero & screen);
      final style = o.text.style;
      final text = o.text.toPlainText().trim();
      // Text cut off by the screen edge is a scroll position, not a design fault.
      final whole = (Offset.zero & screen).inflate(0.5).contains(full.topLeft) && (Offset.zero & screen).inflate(0.5).contains(full.bottomRight);
      if (whole && !box.isEmpty && style?.color != null && text.isNotEmpty && _onTop(tester, o, box)) {
        final counts = <int, int>{};
        final px = (box.left * dpr).floor(), py = (box.top * dpr).floor();
        final pw = (box.width * dpr).floor(), ph = (box.height * dpr).floor();
        for (var y = py; y < py + ph && y < shot.height; y += 2) {
          for (var x = px; x < px + pw && x < shot.width; x += 2) {
            final c = pixel(x, y).toARGB32();
            counts[c] = (counts[c] ?? 0) + 1;
          }
        }
        if (counts.isNotEmpty) {
          final bg = Color(counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key);
          final fg = Color.alphaBlend(style!.color!, bg);
          final size = style.fontSize ?? 14;
          final bold = (style.fontWeight?.value ?? 400) >= 700;
          final need = size >= 18 || (bold && size >= 14) ? 3.0 : 4.5;
          final ratio = contrast(fg, bg);
          if (ratio < need) {
            final short = text.length > 30 ? '${text.substring(0, 30)}…' : text;
            out.add('"$short": ${ratio.toStringAsFixed(2)}:1, needs $need:1 (${size}sp)');
          }
        }
      }
    }
    o.visitChildren(visit);
  }

  visit(tester.binding.rootElement!.renderObject!);
  return out.toList();
}

Future<void> _save(ui.Image image, String path) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// All of a phone's screens side by side, a third of full size, with names.
Future<void> _contactSheet(String path, List<(String, ui.Image)> shots) async {
  const gap = 40.0, caption = 56.0, scale = 1 / 3;
  final w = shots.first.$2.width * scale, h = shots.first.$2.height * scale;
  final cols = shots.length < 4 ? shots.length : 4;
  final rows = (shots.length / cols).ceil();
  final size = Size(gap + cols * (w + gap), gap + rows * (h + caption + gap));
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE4E0D8));
  for (var i = 0; i < shots.length; i++) {
    final x = gap + (i % cols) * (w + gap), y = gap + (i ~/ cols) * (h + caption + gap);
    final label = TextPainter(
      text: TextSpan(text: shots[i].$1, style: const TextStyle(fontFamily: 'Roboto', fontSize: 28, color: Color(0xFF171614))),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(x, y));
    final img = shots[i].$2;
    canvas.drawImageRect(img, Offset.zero & Size(img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(x, y + caption, w, h), Paint()..filterQuality = FilterQuality.medium);
  }
  final sheet = await recorder.endRecording().toImage(size.width.ceil(), size.height.ceil());
  await _save(sheet, path);
}

void main() {
  final shotsDir = Platform.environment['SYL_SHOTS'];
  final shots = <String, List<(String, ui.Image)>>{};

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false; // the app's font is bundled in assets/fonts
    final fonts = _materialFonts;
    await _loadFont('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
    await _loadFont('Roboto', ['$fonts/Roboto-Regular.ttf', '$fonts/Roboto-Medium.ttf', '$fonts/Roboto-Bold.ttf']);
  });

  for (final device in devices) {
    for (final s in scenarios) {
      testWidgets('${device.name} ${s.name}', (tester) async {
        tester.view.physicalSize = device.size * device.pixelRatio;
        tester.view.devicePixelRatio = device.pixelRatio;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ChangeNotifierProvider<LibraryStore>.value(
          value: s.store(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: Syl.theme(),
            home: const HomeShell(),
          ),
        ));
        await tester.runAsync(GoogleFonts.pendingFonts);
        await tester.pumpAndSettle();
        await s.open(tester);
        await tester.runAsync(GoogleFonts.pendingFonts);
        await tester.pumpAndSettle();

        final issues = <String>[];
        for (final g in [androidTapTargetGuideline, labeledTapTargetGuideline]) {
          final result = await g.evaluate(tester);
          if (!result.passed) issues.add((result.reason ?? g.description).trim());
        }
        for (final text in _noFont(tester, device.size)) {
          issues.add('no app font (shows in the system font): $text');
        }
        for (final small in _smallText(tester, device.size)) {
          issues.add('text under ${minTextSize}sp: $small');
        }

        // The root navigator holds the screen plus any sheet or dialog on top of it.
        final image = (await tester.runAsync(() => captureImage(tester.element(find.byType(Navigator).first))))!;
        final pixels = (await tester.runAsync(() => image.toByteData()))!;
        issues.addAll(_lowContrast(tester, image, pixels, device.size, device.pixelRatio).map((i) => 'low contrast: $i'));
        if (shotsDir != null) {
          await tester.runAsync(() => _save(image, '$shotsDir/${device.name}/${s.name}.png'));
          (shots[device.name] ??= []).add((s.name, image));
        }
        expect(issues, isEmpty, reason: issues.join('\n'));
      });
    }
  }

  tearDownAll(() async {
    if (shotsDir != null) {
      for (final entry in shots.entries) {
        await _contactSheet('$shotsDir/sheet-${entry.key}.png', entry.value);
      }
    }
  });
}
