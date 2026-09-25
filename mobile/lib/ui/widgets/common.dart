import 'package:flutter/material.dart';

import '../../theme/syl_theme.dart';

/// Round 44px icon button (white on paper, or translucent on a coloured header).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.background = Syl.white,
    this.foreground = Syl.ink,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 21, color: foreground, semanticLabel: tooltip)),
        ),
      ),
    );
  }
}

/// Small rounded label like "Character" or "Q204274".
class SoftTag extends StatelessWidget {
  const SoftTag(this.label, {super.key, this.dot, this.background, this.foreground = Syl.ink});
  final String label;
  final Color? dot;
  final Color? background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? Syl.ink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot != null) ...[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: foreground)),
        ),
      ]),
    );
  }
}

/// Pill used for the type filters.
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.selected, required this.onTap, this.dot});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Syl.ink : Syl.white,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Syl.paper : Syl.ink,
                  )),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "CH 3" block used next to facts.
class ChapterBadge extends StatelessWidget {
  const ChapterBadge(this.chapter, {super.key, this.color});
  final int chapter;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: color ?? Syl.mint, borderRadius: Syl.r14),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('CH', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, height: 1)),
        Text('$chapter', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.1)),
      ]),
    );
  }
}

/// White circle with an initial.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar(this.initial, {super.key, this.size = 40, this.background = Syl.white});
  final String initial;
  final double size;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(initial, style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.42)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
      if (trailing != null) trailing!,
    ]);
  }
}

/// Small white pill button ("+ Add fact").
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, required this.onTap, this.icon, this.dark = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Syl.paper : Syl.ink;
    return Material(
      color: dark ? Syl.ink : Syl.white,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 6)],
            Flexible(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
            ),
          ]),
        ),
      ),
    );
  }
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
