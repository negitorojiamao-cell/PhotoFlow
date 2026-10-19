import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photoflow/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testDirectory = Directory.systemTemp.createTempSync('photoflow_test_');

  testWidgets('PhotoFlow displays its gallery shell', (tester) async {
    final library = PhotoLibrary(
      documentsDirectoryProvider: () async => testDirectory,
    );

    await tester.pumpWidget(PhotoFlowApp(library: library));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('PhotoFlow'), findsOneWidget);
    expect(find.text('Your moments,\nyour space.'), findsOneWidget);

    addTearDown(() async {
      if (await testDirectory.exists()) {
        await testDirectory.delete(recursive: true);
      }
    });
  });
}
