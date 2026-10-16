import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ui/widgets/stars.dart';

void main() {
  testWidgets('the left half of a star gives a half star, the right half a whole one', (tester) async {
    double? rating;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: StatefulBuilder(
          builder: (_, set) => StarRatingInput(rating: rating, color: Colors.amber, onChanged: (v) => set(() => rating = v)),
        ),
      ),
    ));
    final box = tester.getRect(find.byType(StarRatingInput));
    Future<void> tapAt(double dx) async {
      await tester.tapAt(Offset(box.left + dx, box.center.dy));
      await tester.pump();
    }

    await tapAt(4 * 48 + 10); // left half of the 5th star
    expect(rating, 4.5);
    await tapAt(2 * 48 + 40); // right half of the 3rd
    expect(rating, 3);
    await tapAt(2 * 48 + 40); // the same again clears it
    expect(rating, null);
  });
}
