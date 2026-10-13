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
      child: MaterialApp(
        title: 'SYL',
        debugShowCheckedModeBanner: false,
        theme: Syl.theme(),
        home: const HomeShell(),
      ),
    );
  }
}
