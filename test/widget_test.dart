import 'package:flutter_test/flutter_test.dart';
import 'package:stream/main.dart';
import 'package:stream/utils/string_utils.dart';

/// Runs smoke tests for the download manager app shell.
void main() {
  testWidgets('Download manager app renders the empty state', (
    WidgetTester tester,
  ) async {
    await StringUtils.load();
    await tester.pumpWidget(const DownloadManagerApp());

    expect(find.text(StringUtils.get('appTitle')), findsOneWidget);
    expect(find.text(StringUtils.get('noDownloads')), findsOneWidget);
  });
}
