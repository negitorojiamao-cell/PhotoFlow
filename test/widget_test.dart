import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoflow/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final testDirectory = Directory.systemTemp.createTempSync('photoflow_test_');

  setUp(() {
    channel.setMockMethodCallHandler((call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return testDirectory.path;
      }
      return null;
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  testWidgets('PhotoFlow displays its gallery shell', (tester) async {
    await tester.pumpWidget(const PhotoFlowApp());
    await tester.pumpAndSettle();
    expect(find.text('PhotoFlow'), findsOneWidget);
    expect(find.text('Your moments,\nyour space.'), findsOneWidget);
  });
}
