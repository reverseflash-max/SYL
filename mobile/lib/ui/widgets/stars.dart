import 'package:flutter/material.dart';

/// "4.5 stars", "1 star".
String starsLabel(double rating) {
  final n = rating % 1 == 0 ? rating.toInt().toString() : rating.toString();
  return '$n ${rating == 1 ? 'star' : 'stars'}';
}

/// Five stars showing a rating in half stars.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, required this.size, required this.color, this.emptyColor});
  final double rating;
  final double size;
  final Color color;

  /// The colour of the unfilled stars; [color] if not given.
  final Color? emptyColor;

  static IconData icon(double rating, int i) => rating >= i
      ? Icons.star_rounded
      : rating >= i - 0.5
      ? Icons.star_half_rounded
      : Icons.star_outline_rounded;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${starsLabel(rating)} out of 5',
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 5; i++)
            Icon(icon(rating, i), size: size, color: rating >= i - 0.5 ? color : (emptyColor ?? color)),
        ]),
      );
}

/// Five stars to rate with, in half stars: tap the left half of a star for a
/// half, the right half for the whole star, or slide along them. Tapping the
/// rating you already have clears it.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({super.key, required this.rating, required this.onChanged, required this.color});
  final double? rating;
  final ValueChanged<double?> onChanged;
  final Color color;

  static const _star = 48.0;

  double _at(double dx) => ((dx / (_star / 2)).ceil() / 2).clamp(0.5, 5.0);

  @override
  Widget build(BuildContext context) {
    final r = rating ?? 0;
    return Semantics(
      label: 'Your rating',
      value: rating == null ? 'Not rated' : starsLabel(r),
      increasedValue: starsLabel((r + 0.5).clamp(0.5, 5.0)),
      decreasedValue: rating == null ? null : starsLabel((r - 0.5).clamp(0.5, 5.0)),
      onIncrease: r < 5 ? () => onChanged((r + 0.5).clamp(0.5, 5.0)) : null,
      onDecrease: r > 0.5 ? () => onChanged(r - 0.5) : null,
      slider: true,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final v = _at(d.localPosition.dx);
          onChanged(v == rating ? null : v);
        },
        onHorizontalDragUpdate: (d) => onChanged(_at(d.localPosition.dx)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 5; i++)
            SizedBox(width: _star, height: _star, child: Icon(StarRow.icon(r, i), size: 34, color: color)),
        ]),
      ),
    );
  }
}
