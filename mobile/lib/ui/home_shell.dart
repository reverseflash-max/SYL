import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'library_screen.dart';
import 'map_screen.dart';
import 'reading_screen.dart';
import 'sheets.dart';

/// Three tabs under a floating black pill: Library, Map, Reading. The yellow
/// button adds a fact from anywhere.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final pages = [
      LibraryScreen(onOpenReading: () => setState(() => _tab = 2)),
      const MapScreen(),
      const ReadingScreen(),
    ];
    return Scaffold(
      body: store.loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              IndexedStack(index: _tab, children: pages),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom + 20,
                child: Center(child: _PillNav(tab: _tab, onTab: (i) => setState(() => _tab = i))),
              ),
            ]),
    );
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
        color: Syl.ink,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: Syl.ink.withValues(alpha: 0.28), blurRadius: 40, offset: const Offset(0, 16))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < _items.length; i++) ...[
          _NavItem(icon: _items[i].$1, label: _items[i].$2, selected: tab == i, onTap: () => onTab(i)),
          const SizedBox(width: 4),
        ],
        Tooltip(
          message: 'Add a fact',
          child: Material(
            color: Syl.butter,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => showQuickAdd(context),
              child: const SizedBox(width: 48, height: 48, child: Icon(Icons.add, color: Syl.ink, size: 26, semanticLabel: 'Add a fact')),
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
        color: selected ? Syl.paper : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 13),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 21, color: selected ? Syl.ink : Syl.paper),
              if (selected) ...[
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Syl.ink)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
