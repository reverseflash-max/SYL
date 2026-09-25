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
  String? _book; // null = all books
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
    if (!_bookInit) {
      _book = store.settings.currentBook;
      _bookInit = true;
    }
    final ents = store.entities.where((e) => _book == null || e.book == _book).toList();
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
              '${_book ?? 'All books'}${store.spoilerChapter != null ? ' · to ch. ${store.spoilerChapter}' : ''}',
              style: const TextStyle(fontSize: 14, color: Syl.muted),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                FilterPill(label: 'All books', selected: _book == null, onTap: () => setState(() => _book = null)),
                for (final b in store.books) ...[
                  const SizedBox(width: 8),
                  FilterPill(label: b, selected: _book == b, onTap: () => setState(() {
                    _book = b;
                    _focusId = null;
                  })),
                ],
              ]),
            ),
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

class _Graph extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final near = <String>{
      for (final x in edges)
        if (x.a == focus.id) x.b else if (x.b == focus.id) x.a,
    };
    final inner = entities.where((e) => near.contains(e.id)).toList();
    final outer = entities.where((e) => e.id != focus.id && !near.contains(e.id)).toList();

    // canvas grows with the number of nodes so pills don't overlap
    final side = math.max(math.min(size.width, size.height), 160.0 + 70.0 * math.max(inner.length, outer.length / 1.6));
    final canvas = Size(math.max(size.width, side), math.max(size.height - 140, side));
    final c = Offset(canvas.width / 2, canvas.height / 2);
    final r1 = math.min(canvas.width, canvas.height) * 0.30;
    final r2 = math.min(canvas.width, canvas.height) * 0.46;

    final pos = <String, Offset>{focus.id: c};
    void ring(List<Entity> list, double r, double phase) {
      for (var i = 0; i < list.length; i++) {
        final a = phase + 2 * math.pi * i / list.length;
        pos[list[i].id] = c + Offset(math.cos(a) * r, math.sin(a) * r * 0.85);
      }
    }

    ring(inner, r1, -math.pi / 2 + 0.6);
    ring(outer, r2, -math.pi / 2 + 0.2);

    return Stack(children: [
      InteractiveViewer(
        transformationController: controller,
        constrained: false,
        minScale: 0.4,
        maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(200),
        child: SizedBox(
          width: canvas.width,
          height: canvas.height,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: CustomPaint(painter: _EdgePainter(edges: edges, pos: pos, focus: focus.id))),
            for (final x in edges)
              if (x.label != null && pos[x.a] != null && pos[x.b] != null)
                _at(_labelPoint(pos[x.a]!, pos[x.b]!), SoftTag(x.label!, background: Syl.ink, foreground: Syl.paper)),
            for (final e in entities)
              if (pos[e.id] != null)
                _at(pos[e.id]!, _Node(entity: e, focused: e.id == focus.id, facts: e.visibleFacts(store.spoilerChapter).length, onTap: () => onTap(e))),
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

  Widget _at(Offset p, Widget child) => Positioned(
        left: p.dx,
        top: p.dy,
        child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: child),
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
  const _Node({required this.entity, required this.focused, required this.facts, required this.onTap});
  final Entity entity;
  final bool focused;
  final int facts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: focused ? 'Open ${entity.name}' : 'Focus ${entity.name}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          decoration: BoxDecoration(
            color: Syl.cardColor(entity.id),
            borderRadius: BorderRadius.circular(22),
            border: focused ? Border.all(color: Syl.ink, width: 3) : null,
            boxShadow: [BoxShadow(color: Syl.ink.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            InitialAvatar(entity.initial, size: focused ? 40 : 34),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(entity.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: focused ? 17 : 15, fontWeight: FontWeight.w800, color: Syl.ink)),
              ),
              Text(facts == 0 ? 'no facts yet' : '$facts ${facts == 1 ? 'fact' : 'facts'}',
                  style: const TextStyle(fontSize: 12, color: Syl.ink)),
            ]),
          ]),
        ),
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
