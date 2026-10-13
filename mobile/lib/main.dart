import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'state/library_store.dart';
import 'theme/syl_theme.dart';
import 'ui/home_shell.dart';

void main() {
  // The font ships in assets/fonts; never fetch it from the internet.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const SylApp());
}

class SylApp extends StatelessWidget {
  const SylApp({super.key, this.store});

  /// Tests can pass a pre-built store.
  final LibraryStore? store;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LibraryStore>(
      create: (_) => (store ?? LibraryStore())..load(),
      child: Selector<LibraryStore, String>(
        selector: (_, s) => s.settings.appearance,
        builder: (_, appearance, __) => MaterialApp(
          title: 'SYL',
          debugShowCheckedModeBanner: false,
          theme: Syl.theme(),
          darkTheme: Syl.theme(dark: true),
          themeAnimationDuration: Duration.zero, // the tree rebuilds per mode; no cross-fade
          themeMode: switch (appearance) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          builder: (context, child) => SylMode(dark: Theme.of(context).brightness == Brightness.dark, child: child!),
          home: const HomeShell(),
        ),
      ),
    );
  }
}

/// Points Syl's colours at the mode on show. Screens read those colours
/// directly, so the whole tree is rebuilt (keyed by mode) when it changes.
class SylMode extends StatelessWidget {
  const SylMode({super.key, required this.dark, required this.child});
  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Syl.dark = dark;
    return KeyedSubtree(key: ValueKey(dark), child: child);
  }
}
