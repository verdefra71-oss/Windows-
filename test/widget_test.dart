import 'package:flutter_test/flutter_test.dart';
import 'package:preventivi_app/main.dart';

void main() {
  testWidgets('Preventivi app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const PreventiviApp());
    expect(find.byType(PreventiviApp), findsOneWidget);
  });
}
