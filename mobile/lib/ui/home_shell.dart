import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'books_screen.dart';
import 'library_screen.dart';
import 'map_screen.dart';
import 'new_entity_screen.dart';
import 'settings_screen.dart';
import 'sheets.dart';
import 'widgets/keyboard.dart';

/// Four tabs under a floating pill: Library, Map, Books, Settings. Swipe
/// sideways to move between them. The yellow + opens a small menu: a new
/// book, a new character (or other entry) or a new fact, from anywhere.
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
    dropFocus(); // a text box on the tab you leave keeps no hold on the keyboard
    setState(() => _tab = tab);
    _pages.animateToPage(tab, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final pages = [
      LibraryScreen(onOpenReading: () => _goTo(2)),
      const MapScreen(),
      const BooksScreen(),
      const SettingsScreen(),
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
                  onPageChanged: (i) {
                    dropFocus();
                    setState(() => _tab = i);
                  },
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
    (Icons.menu_book_outlined, 'Books'),
    (Icons.tune, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Syl.inverse,
        borderRadius: BorderRadius.circular(32),
        // a faint edge, so the bar still shows against the Map's night sky
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 40, offset: const Offset(0, 16))],
      ),
      // On a very narrow screen the whole bar shrinks a little rather than overflow.
      child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < _items.length; i++) ...[
          _NavItem(icon: _items[i].$1, label: _items[i].$2, selected: tab == i, onTap: () => onTab(i)),
          const SizedBox(width: 4),
        ],
        Tooltip(
          message: 'Add',
          child: Material(
            color: Syl.accent,
            shape: const CircleBorder(),
            child: Builder(
              builder: (button) => InkWell(
                customBorder: const CircleBorder(),
                onTap: () => showAddMenu(button),
                child: const SizedBox(width: 48, height: 48, child: Icon(Icons.add, color: Syl.onAccent, size: 26, semanticLabel: 'Add')),
              ),
            ),
          ),
        ),
      ])),
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

/// The + menu: the + turns into a ×, and a narrow column of choices rises
/// above it, one after another: a new book, a new character (or place,
/// item...) or a new fact.
Future<void> showAddMenu(BuildContext button) async {
  final box = button.findRenderObject() as RenderBox;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final choice = await showGeneralDialog<String>(
    context: button,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, _) => _AddMenu(button: rect, animation: animation),
  );
  if (!button.mounted) return;
  switch (choice) {
    case 'book':
      await openNewBook(button);
    case 'entry':
      await Navigator.push(button, MaterialPageRoute(builder: (_) => const NewEntityScreen()));
    case 'fact':
      await showQuickAdd(button);
  }
}

class _AddMenu extends StatelessWidget {
  const _AddMenu({required this.button, required this.animation});
  final Rect button;
  final Animation<double> animation;

  static const _items = [
    ('fact', Icons.edit_note, 'New fact'),
    ('entry', Icons.person_add_alt, 'New character'),
    ('book', Icons.menu_book_outlined, 'New book'),
  ];

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Stack(children: [
      // The choices, nearest first, each rising in a moment after the one below.
      Positioned(
        right: screen.width - button.right,
        bottom: screen.height - button.top + 12,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          for (var i = _items.length - 1; i >= 0; i--) ...[
            _rise(i, _Choice(icon: _items[i].$2, label: _items[i].$3, onTap: () => Navigator.pop(context, _items[i].$1))),
            if (i > 0) const SizedBox(height: 10),
          ],
        ]),
      ),
      // The + itself, turning into a × (tap it to close).
      Positioned.fromRect(
        rect: button,
        child: Material(
          color: Syl.accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.pop(context),
            child: RotationTransition(
              turns: Tween(begin: 0.0, end: 0.125).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
              child: const Icon(Icons.add, color: Syl.onAccent, size: 26, semanticLabel: 'Close menu'),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _rise(int i, Widget child) {
    final start = i * 0.15;
    final a = CurvedAnimation(parent: animation, curve: Interval(start, (start + 0.6).clamp(0, 1), curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: a,
      child: SlideTransition(position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(a), child: child),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Syl.white,
      shape: const StadiumBorder(),
      elevation: 2,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: SizedBox(
            height: 52,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Syl.paper, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: Syl.ink),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
