import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import 'books_screen.dart';
import 'widgets/common.dart';
import 'widgets/stars.dart';

/// Opens the share preview for a finished, rated book: the card as it will
/// look in an Instagram Story, and a button that hands the picture to the
/// phone's share menu (Instagram, WhatsApp, saving it...).
Future<void> openShareCard(BuildContext context, Book book) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => ShareCardScreen(book: book)));

class ShareCardScreen extends StatefulWidget {
  const ShareCardScreen({super.key, required this.book});
  final Book book;

  @override
  State<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<ShareCardScreen> {
  final _card = GlobalKey();
  bool _sharing = false;

  /// The card at Story size, 1080 x 1920, as PNG bytes.
  Future<List<int>> _png() async {
    final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: ShareCard.storySize.width / boundary.size.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  static const _instagram = MethodChannel('syl/instagram');

  /// Instagram's Story share is an Android intent; elsewhere only the share menu shows.
  bool get _canStory => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Saves the card as a PNG in the app's cache and returns the file.
  Future<File> _file() async {
    final bytes = await _png();
    final dir = await getTemporaryDirectory();
    final slug = widget.book.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final file = File('${dir.path}/syl-$slug.png');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _sharing = true);
    try {
      await job();
    } catch (e) {
      if (mounted) showMessage(context, 'Could not share the picture: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// The phone's share menu: Instagram, WhatsApp, saving it...
  Future<void> _share() => _run(() async {
        final file = await _file();
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')]));
      });

  /// Straight into Instagram's Story editor with the card loaded.
  Future<void> _shareToStory() => _run(() async {
        final file = await _file();
        final opened = await _instagram.invokeMethod<bool>('shareToStory', {'path': file.path});
        if (opened != true && mounted) {
          showMessage(context, "Instagram isn't on this phone, so here are the other ways to share.");
          await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')]));
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Center(
                child: FittedBox(
                  child: RepaintBoundary(key: _card, child: ShareCard(book: widget.book)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_canStory) ...[
                FilledButton.icon(
                  onPressed: _sharing ? null : _shareToStory,
                  icon: const InstagramGlyph(size: 20),
                  label: Text(_sharing ? 'Making the picture...' : 'Share to Instagram Story'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('More ways to share'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ] else
                FilledButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(_sharing ? 'Making the picture...' : 'Share'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// "Night poster": the book's cover under a night sky, with the title, author,
/// your stars and when you finished it. Laid out at 360 x 640 and saved at
/// three times that, the size of an Instagram Story.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.book});
  final Book book;

  static const size = Size(360, 640);
  static const storySize = Size(1080, 1920);

  static const _top = Color(0xFF121830);
  static const _mid = Color(0xFF1B2240);
  static const _glow = Color(0xFF2A3566);
  static const _ink = Color(0xFFF2EEE6);
  static const _muted = Color(0xFFA9B0CC);

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String? get _finished {
    final d = DateTime.tryParse(book.updatedAt);
    return d == null ? null : '${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final rating = book.rating ?? 0;
    final finished = _finished;
    final text = Theme.of(context).textTheme;
    return MediaQuery(
      // The card looks the same whatever the phone's text size.
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox.fromSize(
        size: size,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 1),
              radius: 1.25,
              colors: [_glow, _mid, _top],
              stops: [0, 0.45, 1],
            ),
          ),
          child: Stack(children: [
            const Positioned.fill(child: CustomPaint(painter: _NightSky())),
            Positioned(
              left: 30,
              right: 30,
              top: 90,
              height: 280,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(colors: [const Color(0xFF4A6FD9).withValues(alpha: 0.35), const Color(0x004A6FD9)]),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 64,
              child: Center(child: BookCoverImage(book: book, width: 180)),
            ),
            Positioned(
              left: 28,
              right: 28,
              top: 368,
              child: Column(children: [
                Text(book.title,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineMedium?.copyWith(
                        color: _ink, fontSize: book.title.length > 28 ? 24 : 29, height: 1.02, letterSpacing: -1)),
                if (book.author.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(book.author, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: _muted, fontSize: 14)),
                ],
                const SizedBox(height: 16),
                StarRow(rating: rating, size: 34, color: _ink, emptyColor: _muted.withValues(alpha: 0.6)),
                if (finished != null) ...[
                  const SizedBox(height: 10),
                  Text('FINISHED · ${finished.toUpperCase()}',
                      style: text.labelMedium?.copyWith(color: _muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.8)),
                ],
              ]),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 26,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const CustomPaint(size: Size(18, 18), painter: _SylMark(color: Color(0xFFC9CEE2))),
                const SizedBox(width: 7),
                Text('SYL', style: text.titleSmall?.copyWith(color: const Color(0xFFC9CEE2), fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A scatter of faint stars, the same every time.
class _NightSky extends CustomPainter {
  const _NightSky();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 46; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height * 0.62);
      paint.color = Colors.white.withValues(alpha: 0.18 + rnd.nextDouble() * 0.45);
      canvas.drawCircle(p, 0.5 + rnd.nextDouble() * 0.9, paint);
    }
  }

  @override
  bool shouldRepaint(_NightSky old) => false;
}

/// SYL's mark: three stars joined into a small constellation.
class _SylMark extends CustomPainter {
  const _SylMark({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final a = Offset(12 * s, 5 * s), b = Offset(5 * s, 17 * s), c = Offset(19 * s, 17 * s);
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.4 * s
      ..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..addPolygon([a, b, c], true), line);
    final dot = Paint()..color = color;
    for (final p in [a, b, c]) {
      canvas.drawCircle(p, 2.4 * s, dot);
    }
  }

  @override
  bool shouldRepaint(_SylMark old) => old.color != color;
}

/// Instagram's glyph (rounded square, lens, flash dot) in the colour of the
/// text around it, as Instagram's brand guide allows for "share to" buttons.
class InstagramGlyph extends StatelessWidget {
  const InstagramGlyph({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(size: Size.square(size), painter: _InstagramPainter(IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color!)),
      );
}

class _InstagramPainter extends CustomPainter {
  const _InstagramPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(3 * s, 3 * s, 18 * s, 18 * s), Radius.circular(5 * s)), line);
    canvas.drawCircle(Offset(12 * s, 12 * s), 4.2 * s, line);
    canvas.drawCircle(Offset(17.2 * s, 6.8 * s), 1.3 * s, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_InstagramPainter old) => old.color != color;
}
