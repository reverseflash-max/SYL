import 'package:flutter/material.dart';

/// The keyboard should only open when you tap a text box. Flutter gives focus
/// back to the last text box whenever a menu, dropdown, sheet or dialog
/// closes, so picking a book from a dropdown could pop the keyboard up. These
/// helpers let go of the focus first, everywhere in the app.

/// Lets go of the focused text box (closing the keyboard).
void dropFocus() => FocusManager.instance.primaryFocus?.unfocus();

/// Lets go of the focus whenever a screen, sheet, dialog, menu or dropdown
/// opens, so nothing hands it back to a text box when that closes.
class DropFocusOnPush extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => dropFocus();
}

/// Tapping anywhere that isn't a text box or a button closes the keyboard.
class TapAwayToCloseKeyboard extends StatelessWidget {
  const TapAwayToCloseKeyboard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      GestureDetector(behavior: HitTestBehavior.translucent, onTap: dropFocus, child: child);
}
