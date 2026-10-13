import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'library_screen.dart';
import 'map_screen.dart';
import 'reading_screen.dart';
import 'sheets.dart';

/// Three tabs under a floating black pill: Library, Map, Reading. Swipe
/// sideways to move between them. The yellow button adds a fact from anywhere.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _pages = PageController();
  Drag? _drag;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int tab) {
    setState(() => _tab = tab);
    _pages.animateToPage(tab, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final pages = [
      LibraryScreen(onOpenReading: () => _goTo(2)),
      const MapScreen(),
      const ReadingScreen(),
    ];
    return Scaffold(
      body: store.loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              // The page view doesn't drag itself: this recognizer drives it, so a swipe that
              // starts inside a NoTabSwipe area (the map) pans that instead of changing tab.
              RawGestureDetector(
                gestures: {
                  _TabSwipeRecognizer: GestureRecognizerFactoryWithHandlers<_TabSwipeRecognizer>(
                    _TabSwipeRecognizer.new,
                    (r) => r
                      ..onStart = ((d) => _drag = _pages.position.drag(d, () => _drag = null))
                      ..onUpdate = ((d) => _drag?.update(d))
                      ..onEnd = ((d) => _drag?.end(d))
                      ..onCancel = (() => _drag?.cancel()),
                  ),
                },
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _tab = i),
                  children: [for (final page in pages) _KeepAlive(child: page)],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom + 20,
                child: Center(child: _PillNav(tab: _tab, onTab: _goTo)),
              ),
            ]),
    );
  }
}

/// Swipes that start inside this child don't change tab (used around the map,
/// which needs sideways drags for panning).
class NoTabSwipe extends SingleChildRenderObjectWidget {
  const NoTabSwipe({super.key, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderNoTabSwipe();
}

class _RenderNoTabSwipe extends RenderProxyBox {}

class _TabSwipeRecognizer extends HorizontalDragGestureRecognizer {
  @override
  bool isPointerAllowed(PointerEvent event) {
    final hits = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hits, event.position, event.viewId);
    if (hits.path.any((entry) => entry.target is _RenderNoTabSwipe)) return false;
    return super.isPointerAllowed(event);
  }
}

/// Keeps a tab's state (scroll position, unsaved text, map position) while it is off screen.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _PillNav extends StatelessWidget {
  const _PillNav({required this.tab, required this.onTab});
  final int tab;
  final ValueChanged<int> onTab;

  static const _items = [
    (Icons.grid_view_rounded, 'Library'),
    (Icons.hub_outlined, 'Map'),
    (Icons.menu_book_outlined, 'Reading'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Syl.inverse,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 40, offset: const Offset(0, 16))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < _items.length; i++) ...[
          _NavItem(icon: _items[i].$1, label: _items[i].$2, selected: tab == i, onTap: () => onTab(i)),
          const SizedBox(width: 4),
        ],
        Tooltip(
          message: 'Add a fact',
          child: Material(
            color: Syl.accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => showQuickAdd(context),
              child: SizedBox(width: 48, height: 48, child: Icon(Icons.add, color: Syl.onAccent, size: 26, semanticLabel: 'Add a fact')),
            ),
          ),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: selected ? Syl.onInverse : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 48,
            constraints: const BoxConstraints(minWidth: 48),
            padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 13),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 21, color: selected ? Syl.inverse : Syl.onInverse),
              if (selected) ...[
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Syl.inverse)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
