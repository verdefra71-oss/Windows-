import 'package:flutter_test/flutter_test.dart';
import 'package:preventivi_app/main.dart';

void main() {
  testWidgets('avvio dell\'app', (WidgetTester tester) async {
    await tester.pumpWidget(const PreventiviApp());
    await tester.pump();
    expect(find.byType(PreventiviApp), findsOneWidget);
  });
}
