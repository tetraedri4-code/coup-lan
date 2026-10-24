import 'package:coup_lan/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home screen shows host button', (tester) async {
    await tester.pumpWidget(const CoupApp());
    expect(find.text('Host a game'), findsOneWidget);
    expect(find.text('COUP'), findsOneWidget);
  });
}
