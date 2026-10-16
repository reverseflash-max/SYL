import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'entity_screen.dart';
import 'home_shell.dart' show NoTabSwipe;

/// The book as a night sky. Every entry is a star (brighter with more
/// facts), saved links are constellation lines, names mentioned in facts are
/// dotted lines. The selected star sits in the middle with what it touches
/// around it. Whatever is past your chapter is still below the horizon.
/// Tap a star to focus it, tap again to open it.
///
/// The sky is the same night indigo as the rest of the app.
class _Sky {
  static const ground = Color(0xFF1B2240);
  static const star = Color(0xFFE9EEEC);
  static const dim = Color(0xFFB8C3C1);
  static const muted = Color(0xFFA9B0CC);
  static const faint = Color(0xFF5A6289);
  static const teal = Color(0xFF86D6C6);
  static const card = Color(0xFF121830);
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _Edge {
  final String a, b;
  final String? label;
  final bool dotted;
  const _Edge(this.a, this.b, this.label, this.dotted);
}

class _MapScreenState extends State<MapScreen> {
  String? _focusId;
  String? _book; // the book on the map; null = entries with no book
  bool _bookInit = false;
  final _viewer = TransformationController();

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    // One book at a time; entries without a book get their own "No book" choice.
    final choices = <String?>[...store.books, if (store.entities.any((e) => e.book == null)) null];
    if (!_bookInit || !choices.contains(_book)) {
      final current = store.settings.currentBook;
      _book = choices.contains(current) || choices.isEmpty ? current : choices.first;
      _bookInit = true;
    }
    final ents = store.entities.where((e) => _book == null ? e.book == null : sameTitle(e.book, _book)).toList();
    final ids = {for (final e in ents) e.id};

    // edges
    final edges = <_Edge>[];
    for (final r in store.relationships) {
      if (!ids.contains(r.source) || !ids.contains(r.target)) continue;
      final shield = store.chapterFor(_book);
      if (shield != null && r.chapter != null && r.chapter! > shield) continue;
      edges.add(_Edge(r.source, r.target, r.type, false));
    }
    for (final e in ents) {
      for (final m in store.mentionsIn(e)) {
        if (!ids.contains(m.id)) continue;
        final already = edges.any((x) => (x.a == e.id && x.b == m.id) || (x.a == m.id && x.b == e.id));
        if (!already) edges.add(_Edge(e.id, m.id, null, true));
      }
    }

    // pick a focus: the requested one, else the most connected
    Entity? focus = _focusId == null ? null : ents.where((e) => e.id == _focusId).firstOrNull;
    if (focus == null && ents.isNotEmpty) {
      final degree = {for (final e in ents) e.id: edges.where((x) => x.a == e.id || x.b == e.id).length};
      focus = (ents.toList()..sort((a, b) => degree[b.id]!.compareTo(degree[a.id]!))).first;
    }

    final cap = store.chapterFor(_book);
    final below = cap == null
        ? 0
        : store.relationships.where((r) => ids.contains(r.source) && ids.contains(r.target) && (r.chapter ?? 0) > cap).length;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: _Sky.ground,
        child: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _DustPainter())),
          SafeArea(
            bottom: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _BookChip(
                    label: _book ?? 'No book',
                    choices: choices,
                    onPick: (b) => setState(() {
                      _book = b;
                      _focusId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  const Text('Map',
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1, color: _Sky.star)),
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: cap == null ? 'Everything you have noted' : 'What you can see up to '),
                      if (cap != null)
                        TextSpan(text: 'ch. $cap', style: const TextStyle(fontWeight: FontWeight.w700, color: _Sky.teal)),
                    ]),
                    style: const TextStyle(fontSize: 14, color: _Sky.muted),
                  ),
                ]),
              ),
              Expanded(
                child: ents.isEmpty
                    ? const Center(child: Text('Nothing to map yet.', style: TextStyle(color: _Sky.muted)))
                    : LayoutBuilder(builder: (context, box) {
                        return _Graph(
                          size: box.biggest,
                          entities: ents,
                          edges: edges,
                          focus: focus!,
                          controller: _viewer,
                          chapter: cap,
                          below: below,
                          onTap: (e) {
                            if (e.id == focus!.id) {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => EntityScreen(entityId: e.id)));
                            } else {
                              setState(() => _focusId = e.id);
                            }
                          },
                        );
                      }),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// "The Lord of the Rings ⌄": the book on the map, tap to pick another.
class _BookChip extends StatelessWidget {
  const _BookChip({required this.label, required this.choices, required this.onPick});
  final String label;
  final List<String?> choices;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final many = choices.length > 1;
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(side: BorderSide(color: Color(0xFF3A4270))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: !many
            ? null
            : () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheet) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final b in choices)
                        ListTile(
                          title: Text(b ?? 'No book'),
                          trailing: b == label || (b == null && label == 'No book') ? const Icon(Icons.check) : null,
                          onTap: () {
                            Navigator.pop(sheet);
                            onPick(b);
                          },
                        ),
                    ]),
                  ),
                ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _Sky.star)),
            ),
            if (many) ...[
              const SizedBox(width: 6),
              const Icon(Icons.expand_more, size: 18, color: _Sky.star, semanticLabel: 'Choose a book'),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Faint background stars, the same every time.
class _DustPainter extends CustomPainter {
  const _DustPainter();

  @override
  void paint(Canvas canvas, Size size) {
    var s = 7;
    double rnd() => (s = (s * 16807) % 2147483647) / 2147483647;
    final p = Paint();
    for (var i = 0; i < 110; i++) {
      final x = rnd() * size.width, y = rnd() * size.height, r = 0.5 + rnd() * 0.9;
      p.color = _Sky.faint.withValues(alpha: 0.3 + rnd() * 0.5);
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }

  @override
  bool shouldRepaint(_DustPainter old) => false;
}

/// Node footprint used for spacing: the circle plus the name underneath.
const double _nodeWidth = 96;
const double _avatar = 26, _avatarFocused = 40;

/// Space between neighbouring nodes on a ring, and between the two rings.
const double _nodeGap = _nodeWidth + 24;

class _Graph extends StatefulWidget {
  const _Graph({
    required this.size,
    required this.entities,
    required this.edges,
    required this.focus,
    required this.onTap,
    required this.controller,
    required this.chapter,
    required this.below,
  });

  final int? chapter;

  /// Links past your chapter, still below the horizon.
  final int below;
  final Size size;
  final List<Entity> entities;
  final List<_Edge> edges;
  final Entity focus;
  final ValueChanged<Entity> onTap;
  final TransformationController controller;

  @override
  State<_Graph> createState() => _GraphState();
}

class _GraphState extends State<_Graph> with TickerProviderStateMixin {
  /// The view that frames the selected star; Recenter glides back to it.
  Matrix4? _home;
  late final AnimationController _glide = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  Animation<Matrix4>? _glideTo;

  void _recenter() {
    final home = _home;
    if (home == null) return;
    _glideTo = Matrix4Tween(begin: widget.controller.value.clone(), end: home)
        .animate(CurvedAnimation(parent: _glide, curve: Curves.easeOutCubic));
    _glide.forward(from: 0);
  }

  /// Stars glide from where they were to where they now belong when you pick
  /// another one; a star that wasn't there before rises into place.
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 550))
    ..value = 1;
  Map<String, Offset> _from = {}, _to = {};

  @override
  void initState() {
    super.initState();
    _glide.addListener(() {
      if (_glideTo != null) widget.controller.value = _glideTo!.value;
    });
  }

  @override
  void dispose() {
    _move.dispose();
    _glide.dispose();
    super.dispose();
  }

  Map<String, Offset> _at(double t) => {
        for (final id in _to.keys) id: Offset.lerp(_from[id] ?? _to[id]!, _to[id]!, t)!,
      };

  void _moveTo(Map<String, Offset> pos) {
    if (mapEquals(pos, _to)) return;
    if (_to.isEmpty) {
      _from = _to = pos;
      return;
    }
    final now = _at(Curves.easeOutCubic.transform(_move.value));
    _from = {for (final id in pos.keys) id: now[id] ?? pos[id]! + const Offset(0, 60)};
    _to = pos;
    _move.forward(from: 0);
  }

  /// The visible map area: the focus card and the bottom bar cover the rest.
  static const double _coveredBottom = 200;

  (String, Offset, double)? _centred; // focus, canvas point and zoom last applied

  /// Up to this many entries share one ring, which fits on a phone screen.
  static const int _oneRingMax = 7;

  /// Radius at which [count] nodes fit around a circle without touching.
  static double _ringRadius(int count, double minimum) =>
      count < 2 ? minimum : math.max(minimum, (_nodeGap / 2) / math.sin(math.pi / count));

  /// Put [point] in the middle of the visible area, zoomed out just enough
  /// to show [reachX] and [reachY] around it (never below 60%).
  void _centreOn(String id, Offset point, double reachX, double reachY) {
    final visibleH = math.max(120.0, widget.size.height - _coveredBottom);
    final scale = math.min(1.0, math.min(widget.size.width / 2 / reachX, visibleH / 2 / reachY)).clamp(0.6, 1.0);
    if (_centred == (id, point, scale)) return;
    _centred = (id, point, scale);
    _home = Matrix4.identity()
      ..translateByDouble(widget.size.width / 2, visibleH / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-point.dx, -point.dy, 0, 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.value = _home!.clone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final focus = widget.focus;
    final edges = widget.edges;
    final near = <String>{
      for (final x in edges)
        if (x.a == focus.id) x.b else if (x.b == focus.id) x.a,
    };
    var inner = widget.entities.where((e) => near.contains(e.id)).toList();
    var outer = widget.entities.where((e) => e.id != focus.id && !near.contains(e.id)).toList();
    final unlinked = {for (final e in outer) e.id};
    // A few entries share one ring (linked ones first); more get a second, outer ring.
    if (inner.length + outer.length <= _oneRingMax) {
      inner = [...inner, ...outer];
      outer = [];
    }

    // Rings sized from the nodes themselves, so nothing overlaps however many there are.
    final r1 = _ringRadius(inner.length, 140);
    final r2 = _ringRadius(outer.length, (inner.isEmpty ? 0 : r1) + _nodeGap + 20);
    final reach = (outer.isEmpty ? r1 : r2) + _nodeWidth;
    final canvas = Size(math.max(widget.size.width, reach * 2), math.max(widget.size.height, reach * 2.4));
    final c = Offset(canvas.width / 2, canvas.height / 2);

    final pos = <String, Offset>{focus.id: c};
    void ring(List<Entity> list, double r, double phase) {
      for (var i = 0; i < list.length; i++) {
        final a = phase + 2 * math.pi * i / list.length;
        // Phones are tall, so rings stretch a little vertically for more room.
        // Each star is nudged by its own id, so the rings read as constellations.
        final h = list[i].id.hashCode;
        final nudge = Offset(((h % 37) - 18).toDouble(), (((h ~/ 37) % 37) - 18).toDouble());
        pos[list[i].id] = c + Offset(math.cos(a) * r, math.sin(a) * r * 1.15) + nudge;
      }
    }

    ring(inner, r1, -math.pi / 2);
    ring(outer, r2, -math.pi / 2 + (inner.isEmpty ? 0 : math.pi / math.max(outer.length, 1)));
    final ringReach = outer.isEmpty ? (inner.isEmpty ? 0.0 : r1) : r2;
    _centreOn(focus.id, c, ringReach + _nodeWidth / 2 + 8, ringReach * 1.15 + 70);
    final risen = {..._from.keys};
    _moveTo(pos);

    return Stack(children: [
      NoTabSwipe(child: InteractiveViewer(
        transformationController: widget.controller,
        constrained: false,
        minScale: 0.4,
        maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(200),
        child: SizedBox(
          width: canvas.width,
          height: canvas.height,
          child: AnimatedBuilder(
            animation: _move,
            builder: (context, _) {
              final t = Curves.easeOutCubic.transform(_move.value);
              final at = _at(t);
              return Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: CustomPaint(painter: _EdgePainter(edges: edges, pos: at, focus: focus.id))),
                for (final e in widget.entities)
                  if (at[e.id] != null)
                    _node(at[e.id]!, e, e.id == focus.id, e.visibleFacts(store.capFor(e)).length, unlinked.contains(e.id),
                        rise: risen.isEmpty || risen.contains(e.id) ? 1 : t),
                // Labels last, so a node can never hide them.
                for (final x in edges)
                  if (x.label != null && at[x.a] != null && at[x.b] != null)
                    _label(_labelPoint(at[x.a]!, at[x.b]!), x.label!, x.a == focus.id || x.b == focus.id),
              ]);
            },
          ),
        ),
      )),
      // Below the horizon the sky doesn't pan, so a sideways swipe there
      // moves to the next tab, as it does on every other page.
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 214,
        child: Listener(behavior: HitTestBehavior.opaque),
      ),
      Positioned(
        top: 8,
        right: 14,
        child: Material(
          color: _Sky.card,
          shape: const CircleBorder(side: BorderSide(color: Color(0xFF3A4270))),
          child: IconButton(
            tooltip: 'Recenter',
            onPressed: _recenter,
            icon: const Icon(Icons.center_focus_strong, color: _Sky.star),
          ),
        ),
      ),
      if (widget.chapter != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 214,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _Sky.faint))),
              child: Row(children: [
                Text('Horizon · ch. ${widget.chapter}', style: const TextStyle(fontSize: 12, color: _Sky.muted)),
                const Spacer(),
                if (widget.below > 0)
                  Text('${widget.below} ${widget.below == 1 ? 'link' : 'links'} still below',
                      style: const TextStyle(fontSize: 12, color: _Sky.muted)),
              ]),
            ),
          ),
        ),
      Positioned(
        left: 18,
        right: 18,
        bottom: 100,
        child: _FocusCard(entity: focus, store: store),
      ),
    ]);
  }

  /// A node is placed by the centre of its circle, so edges meet the circle, not the name.
  Widget _node(Offset p, Entity e, bool focused, int facts, bool unlinked, {double rise = 1}) {
    final avatar = focused ? _avatarFocused : _avatar;
    return Positioned(
      left: p.dx - _nodeWidth / 2,
      top: p.dy - avatar / 2,
      width: _nodeWidth,
      // Entries with no link to the focus are dimmed, so its own connections stand out.
      child: Opacity(
        opacity: (unlinked ? 0.6 : 1) * rise,
        child: _Node(entity: e, focused: focused, facts: facts, avatar: avatar, onTap: () => widget.onTap(e)),
      ),
    );
  }

  Widget _label(Offset p, String text, bool strong) => Positioned(
        left: p.dx,
        top: p.dy,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: IgnorePointer(
            child: Opacity(
              opacity: strong ? 1 : 0.55,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 110),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _Sky.ground.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(10)),
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _Sky.teal)),
              ),
            ),
          ),
        ),
      );

  /// Midpoint of the line drawn by [_EdgePainter].
  static Offset _labelPoint(Offset a, Offset b) => Offset.lerp(a, b, 0.5)!;
}

class _Node extends StatelessWidget {
  const _Node({required this.entity, required this.focused, required this.facts, required this.avatar, required this.onTap});
  final Entity entity;
  final bool focused;
  final int facts;
  final double avatar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final factsText = facts == 0 ? 'no facts yet' : '$facts ${facts == 1 ? 'fact' : 'facts'}';
    final radius = focused ? 8.0 : 3.0 + math.min(facts, 5) * 0.8;
    return Semantics(
      button: true,
      label: '${focused ? 'Open' : 'Focus'} ${entity.name}, $factsText',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // A star: brighter and bigger with more facts; the focused one glows.
          SizedBox(
            width: avatar,
            height: avatar,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: radius * 2,
                height: radius * 2,
                decoration: BoxDecoration(
                  color: facts == 0 ? _Sky.dim : _Sky.star,
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (focused) BoxShadow(color: _Sky.teal.withValues(alpha: 0.55), blurRadius: 22, spreadRadius: 6),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: _Sky.ground.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(entity.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: focused ? 14 : 13, fontWeight: FontWeight.w700, color: facts == 0 ? _Sky.dim : _Sky.star, height: 1.15)),
              Text(factsText, style: const TextStyle(fontSize: 11, color: _Sky.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.entity, required this.store});
  final Entity entity;
  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    final links = store.linksFor(entity.id);
    final mentions = store.mentionsIn(entity);
    final lines = <String>[
      for (final r in links)
        if (store.byId(r.other(entity.id)) case final o?)
          r.source == entity.id ? '${r.type} of ${o.name}' : '${o.name}: ${r.type}',
      for (final m in mentions) 'Mentions ${m.name}',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Sky.card,
        borderRadius: Syl.r20,
        border: Border.all(color: const Color(0xFF2E3765)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(entity.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _Sky.star)),
            Text(lines.isEmpty ? 'No connections yet' : lines.join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _Sky.muted)),
          ]),
        ),
        const SizedBox(width: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _Sky.teal, foregroundColor: const Color(0xFF06201B)),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntityScreen(entityId: entity.id))),
          child: const Text('Open'),
        ),
      ]),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.edges, required this.pos, required this.focus});
  final List<_Edge> edges;
  final Map<String, Offset> pos;
  final String focus;

  @override
  void paint(Canvas canvas, Size size) {
    for (final x in edges) {
      final a = pos[x.a], b = pos[x.b];
      if (a == null || b == null) continue;
      final touchesFocus = x.a == focus || x.b == focus;
      final paint = Paint()
        ..color = (x.dotted ? _Sky.faint : _Sky.teal).withValues(alpha: touchesFocus ? 0.9 : 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = touchesFocus ? 1.6 : 1.2
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
      if (!x.dotted) {
        canvas.drawPath(path, paint);
      } else {
        for (final PathMetric m in path.computeMetrics()) {
          var d = 0.0;
          while (d < m.length) {
            canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), paint);
            d += 9;
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) => old.edges != edges || old.pos != pos || old.focus != focus;
}
