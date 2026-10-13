import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'entity_screen.dart';
import 'widgets/common.dart';

/// Visual relationship map. The selected entry sits in the middle, the
/// things it is linked to or mentions sit around it, everything else is on
/// an outer ring. Solid lines are saved links; dotted lines are names that
/// appear inside facts. Tap a node to focus it, tap again to open it.
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
    final ents = store.entities.where((e) => e.book == _book).toList();
    final ids = {for (final e in ents) e.id};

    // edges
    final edges = <_Edge>[];
    for (final r in store.relationships) {
      if (!ids.contains(r.source) || !ids.contains(r.target)) continue;
      if (store.spoilerChapter != null && r.chapter != null && r.chapter! > store.spoilerChapter!) continue;
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

    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Map', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 44)),
            const SizedBox(height: 4),
            Text(
              '${_book ?? 'No book'}${store.spoilerChapter != null ? ' · to ch. ${store.spoilerChapter}' : ''}',
              style: const TextStyle(fontSize: 14, color: Syl.muted),
            ),
            if (choices.length > 1) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: choices.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => FilterPill(
                    label: choices[i] ?? 'No book',
                    selected: _book == choices[i],
                    onTap: () => setState(() {
                      _book = choices[i];
                      _focusId = null;
                    }),
                  ),
                ),
              ),
            ],
          ]),
        ),
        Expanded(
          child: ents.isEmpty
              ? const Center(child: Text('Nothing to map yet.'))
              : LayoutBuilder(builder: (context, box) {
                  return _Graph(
                    size: box.biggest,
                    entities: ents,
                    edges: edges,
                    focus: focus!,
                    controller: _viewer,
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
    );
  }
}

/// Node footprint used for spacing: the circle plus the name underneath.
const double _nodeWidth = 96;
const double _avatar = 52, _avatarFocused = 64;

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
  });

  final Size size;
  final List<Entity> entities;
  final List<_Edge> edges;
  final Entity focus;
  final ValueChanged<Entity> onTap;
  final TransformationController controller;

  @override
  State<_Graph> createState() => _GraphState();
}

class _GraphState extends State<_Graph> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.value = Matrix4.identity()
        ..translateByDouble(widget.size.width / 2, visibleH / 2, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-point.dx, -point.dy, 0, 1);
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
        pos[list[i].id] = c + Offset(math.cos(a) * r, math.sin(a) * r * 1.15);
      }
    }

    ring(inner, r1, -math.pi / 2);
    ring(outer, r2, -math.pi / 2 + (inner.isEmpty ? 0 : math.pi / math.max(outer.length, 1)));
    final ringReach = outer.isEmpty ? (inner.isEmpty ? 0.0 : r1) : r2;
    _centreOn(focus.id, c, ringReach + _nodeWidth / 2 + 8, ringReach * 1.15 + 70);

    return Stack(children: [
      InteractiveViewer(
        transformationController: widget.controller,
        constrained: false,
        minScale: 0.4,
        maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(200),
        child: SizedBox(
          width: canvas.width,
          height: canvas.height,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: CustomPaint(painter: _EdgePainter(edges: edges, pos: pos, focus: focus.id))),
            for (final e in widget.entities)
              if (pos[e.id] != null)
                _node(pos[e.id]!, e, e.id == focus.id, e.visibleFacts(store.spoilerChapter).length, unlinked.contains(e.id)),
            // Labels last, so a node can never hide them.
            for (final x in edges)
              if (x.label != null && pos[x.a] != null && pos[x.b] != null)
                _label(_labelPoint(pos[x.a]!, pos[x.b]!), x.label!, x.a == focus.id || x.b == focus.id),
          ]),
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
  Widget _node(Offset p, Entity e, bool focused, int facts, bool unlinked) {
    final avatar = focused ? _avatarFocused : _avatar;
    return Positioned(
      left: p.dx - _nodeWidth / 2,
      top: p.dy - avatar / 2,
      width: _nodeWidth,
      // Entries with no link to the focus are dimmed, so its own connections stand out.
      child: Opacity(
        opacity: unlinked ? 0.6 : 1,
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
                decoration: BoxDecoration(color: strong ? Syl.ink : Syl.inkSoft, borderRadius: BorderRadius.circular(10)),
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Syl.paper)),
              ),
            ),
          ),
        ),
      );

  /// Midpoint of the curved edge drawn by [_EdgePainter].
  static Offset _labelPoint(Offset a, Offset b) {
    final mid = Offset.lerp(a, b, 0.5)!;
    final normal = Offset(-(b.dy - a.dy), b.dx - a.dx);
    final len = normal.distance == 0 ? 1.0 : normal.distance;
    return mid + normal / len * 14; // quadratic curve peaks at half the control offset
  }
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
    return Semantics(
      button: true,
      label: '${focused ? 'Open' : 'Focus'} ${entity.name}, $factsText',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: avatar,
            height: avatar,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Syl.cardColor(entity.id),
              shape: BoxShape.circle,
              border: Border.all(color: focused ? Syl.ink : Syl.white, width: focused ? 3 : 2),
              boxShadow: [BoxShadow(color: Syl.ink.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: Text(entity.initial, style: TextStyle(fontWeight: FontWeight.w800, fontSize: avatar * 0.4, color: Syl.ink)),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Syl.paper.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(8)),
            child: Text(entity.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: focused ? 14 : 12.5, fontWeight: FontWeight.w800, color: Syl.ink, height: 1.15)),
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
        color: Syl.white,
        borderRadius: Syl.r20,
        boxShadow: [BoxShadow(color: Syl.ink.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(entity.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(lines.isEmpty ? 'No connections yet' : lines.join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Syl.muted)),
          ]),
        ),
        const SizedBox(width: 10),
        FilledButton(
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
        ..color = Syl.ink.withValues(alpha: touchesFocus ? 0.9 : 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = x.dotted ? 2 : 2.4
        ..strokeCap = StrokeCap.round;
      final mid = Offset.lerp(a, b, 0.5)!;
      final normal = Offset(-(b.dy - a.dy), b.dx - a.dx);
      final len = normal.distance == 0 ? 1.0 : normal.distance;
      final ctrl = mid + normal / len * 28;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, b.dx, b.dy);
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
