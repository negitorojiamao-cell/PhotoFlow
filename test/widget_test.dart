import 'package:flutter_test/flutter_test.dart';
import 'package:photoflow/main.dart';

void main() {
  testWidgets('PhotoFlow displays its gallery shell', (tester) async {
    await tester.pumpWidget(const PhotoFlowApp());
    await tester.pump();
    expect(find.text('PhotoFlow'), findsOneWidget);
    expect(find.text('Your moments,\nyour space.'), findsOneWidget);
  });
}
