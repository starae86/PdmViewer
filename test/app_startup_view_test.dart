import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/app.dart';
import 'package:pdm_viewer/app/state/app_controller.dart';
import 'package:pdm_viewer/app/state/theme_controller.dart';

void main() {
  testWidgets('startup and failure keep the saved dark theme', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'zh',
      'CN',
    );
    addTearDown(() => tester.binding.platformDispatcher.clearLocaleTestValue());
    final directory = Directory.systemTemp.createTempSync('startup_theme_');
    final theme = ThemeController(storagePath: '${directory.path}/theme.json');
    await tester.runAsync(
      () => theme.setAppearance(
        seedColor: Colors.blue,
        fontFamily: null,
        themeMode: ThemeMode.dark,
        backgroundColor: const Color(0xff182024),
      ),
    );
    final startup = Completer<AppController>();
    await tester.pumpWidget(
      PdmReaderApp(startup: startup.future, themeController: theme),
    );
    expect(find.text('正在加载项目…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final context = tester.element(find.byType(Scaffold));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const ValueKey('startup-background')))
          .color,
      const Color(0xff182024),
    );

    startup.completeError(StateError('database unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('database unavailable'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    theme.dispose();
    directory.deleteSync(recursive: true);
  });
}
