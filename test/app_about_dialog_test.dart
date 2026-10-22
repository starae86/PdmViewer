import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/l10n/app_strings.dart';
import 'package:pdm_viewer/app/theme/app_theme.dart';
import 'package:pdm_viewer/ui/widgets/app_about_dialog.dart';

void main() {
  testWidgets('about links, localization and compact themes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    String? opened;
    var success = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      opened = (call.arguments as Map)['url'] as String;
      return success;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    for (final english in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(english ? 'en' : 'zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.build(
            brightness: english ? Brightness.dark : Brightness.light,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppAboutDialog(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('PdmViewer'), findsOneWidget);
      expect(find.text(english ? 'Version 1.0.0' : '版本 1.0.0'), findsOneWidget);
      for (final url in [
        'https://github.com/starae86/PdmViewer',
        'https://gitee.com/starae86/PdmViewer',
        'https://github.com/starae86/PdmViewer/issues',
        'https://github.com/starae86/PdmViewer/releases',
      ]) {
        await tester.ensureVisible(find.text(url));
        await tester.tap(find.text(url));
        await tester.pumpAndSettle();
        expect(opened, url);
      }
      success = false;
      final link = find.text('https://github.com/starae86/PdmViewer/releases');
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(
        find.text(english ? 'Cannot Open Link' : '无法打开链接'),
        findsOneWidget,
      );
      await tester.tap(find.text(english ? 'Close' : '关闭').last);
      await tester.pumpAndSettle();
      expect(find.text('PdmViewer'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(english ? 'Close' : '关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      success = true;
    }
  });
}
