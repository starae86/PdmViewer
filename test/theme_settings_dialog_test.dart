import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/theme/app_theme.dart';
import 'package:pdm_viewer/app/theme/theme_preset.dart';
import 'package:pdm_viewer/app/theme/theme_contrast.dart';
import 'package:pdm_viewer/ui/widgets/theme_settings_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('pdm_viewer/system_fonts'),
          (_) async => ['Arial'],
        );
  });

  Future<void> openDialog(
    WidgetTester tester,
    ValueChanged<ThemeSettingsSelection?> onResult, {
    String? presetId = 'material',
    ThemeContrast contrast = ThemeContrast.medium,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => onResult(
                await showDialog<ThemeSettingsSelection>(
                  context: context,
                  builder: (_) => ThemeSettingsDialog(
                    initial: ThemeSettingsSelection(
                      seedColor: AppTheme.defaultSeedColor,
                      presetId: presetId,
                      contrast: contrast,
                    ),
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  Future<void> selectStyle(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('contrast previews locally and applies the selected level', (
    tester,
  ) async {
    ThemeSettingsSelection? result;
    await openDialog(
      tester,
      (value) => result = value,
      contrast: ThemeContrast.low,
    );
    expect(
      Theme.of(
        tester.element(find.byType(AlertDialog)),
      ).extension<ContrastStyle>()!.level,
      ThemeContrast.low,
    );
    await tester.tap(find.text('高'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(
      Theme.of(
        tester.element(find.byType(AlertDialog)),
      ).extension<ContrastStyle>()!.level,
      ThemeContrast.high,
    );
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(result?.contrast, ThemeContrast.high);
  });

  testWidgets('cancelling discards a contrast change', (tester) async {
    ThemeSettingsSelection? result;
    await openDialog(tester, (value) => result = value);
    await tester.tap(find.text('高'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await openDialog(tester, (value) => result = value);
    expect(
      Theme.of(
        tester.element(find.byType(AlertDialog)),
      ).extension<ContrastStyle>()!.level,
      ThemeContrast.medium,
    );
  });

  testWidgets(
    'reset restores default style, automatic mode and medium contrast',
    (tester) async {
      ThemeSettingsSelection? result;
      await openDialog(
        tester,
        (value) => result = value,
        presetId: 'macos',
        contrast: ThemeContrast.high,
      );
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('绿色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重置'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      final theme = Theme.of(tester.element(find.byType(AlertDialog)));
      expect(theme.extension<ContrastStyle>()!.level, ThemeContrast.medium);
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(result?.presetId, ThemePreset.defaultId);
      expect(result?.themeMode, ThemeMode.system);
      expect(result?.contrast, ThemeContrast.medium);
      expect(result?.fontFamily, isNull);
      expect(result?.accentColor, isNull);
    },
  );

  testWidgets('four styles offer preset accents without background editors', (
    tester,
  ) async {
    await openDialog(tester, (_) {});
    final button = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .first;
    expect(button.items!.map((item) => item.value).toSet(), {
      'workbench',
      'material',
      'fluent',
      'macos',
    });
    expect(find.text('主题色'), findsOneWidget);
    expect(find.byTooltip('自定义主题色'), findsOneWidget);
    expect(find.text('前景色'), findsNothing);
    expect(find.text('背景色'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'style and mode preview together and apply without custom overrides',
    (tester) async {
      ThemeSettingsSelection? result;
      await openDialog(tester, (value) => result = value);
      await selectStyle(tester, 'Fluent Design');
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      final scheme = Theme.of(
        tester.element(find.byType(AlertDialog)),
      ).colorScheme;
      expect(scheme.surface, const Color(0xFF202020));
      expect(scheme.primary, const Color(0xFF60CDFF));
      expect(
        scheme.surfaceContainerLow,
        ThemePreset.find('fluent')!.dark.chrome,
      );
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(result?.presetId, 'fluent');
      expect(result?.themeMode, ThemeMode.dark);
      expect(result?.backgroundColor, isNull);
      expect(result?.foregroundColor, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel discards style selection and existing style is restored on open',
    (tester) async {
      ThemeSettingsSelection? result;
      await openDialog(tester, (value) => result = value, presetId: 'macos');
      expect(find.text('macOS'), findsOneWidget);
      await selectStyle(tester, 'Material Design');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );

  testWidgets(
    'automatic appearance follows system with the same selected style',
    (tester) async {
      ThemeSettingsSelection? result;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await openDialog(tester, (value) => result = value, presetId: 'macos');
      await tester.tap(find.text('自动'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.surface,
        Colors.white,
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.surface,
        const Color(0xFF1E1E1E),
      );
      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(AlertDialog))).brightness,
        Brightness.light,
      );
      await tester.tap(find.text('自动'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(result?.themeMode, ThemeMode.system);
      expect(result?.presetId, 'macos');
    },
  );

  testWidgets('settings remain usable in a short window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openDialog(tester, (_) {});
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test(
    'all palettes retain exact accents, surface layers and readable text',
    () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
      }

      expect(ThemePreset.values.length, 4);
      for (final preset in ThemePreset.values) {
        for (final brightness in Brightness.values) {
          final palette = preset.palette(brightness);
          final theme = AppTheme.build(
            presetId: preset.id,
            brightness: brightness,
          );
          final materialScheme = ColorScheme.fromSeed(
            seedColor: preset.light.accent,
            brightness: brightness,
            surface: palette.background,
          );
          expect(theme.colorScheme.primary, palette.accent);
          expect(theme.colorScheme.surface, palette.background);
          expect(theme.colorScheme.onSurface, palette.foreground);
          expect(theme.colorScheme.surfaceContainerLow, palette.chrome);
          expect(
            theme.colorScheme.primaryContainer,
            preset.id == 'material'
                ? materialScheme.primaryContainer
                : palette.selection,
          );
          expect(
            contrast(palette.foreground, palette.background),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(palette.accent, palette.onAccent),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );

  testWidgets('accent selection preserves style and defaults can be restored', (
    tester,
  ) async {
    ThemeSettingsSelection? result;
    await openDialog(tester, (value) => result = value, presetId: 'fluent');
    await tester.tap(find.byTooltip('绿色'));
    await tester.pumpAndSettle();
    var scheme = Theme.of(tester.element(find.byType(AlertDialog))).colorScheme;
    expect(scheme.surface, Colors.white);
    expect(scheme.primary, isNot(const Color(0xFF0067C0)));
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    scheme = Theme.of(tester.element(find.byType(AlertDialog))).colorScheme;
    expect(scheme.surface, const Color(0xFF202020));
    await tester.tap(find.text('默认'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.primary,
      const Color(0xFF60CDFF),
    );
    await tester.tap(find.byTooltip('绿色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(result?.accentColor, ThemePreset.accents['绿色']);
    expect(result?.presetId, 'fluent');
    expect(result?.themeMode, ThemeMode.dark);
  });

  testWidgets(
    'custom picker opens in a short window and cancel keeps default',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 450));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openDialog(tester, (_) {});
      await tester.ensureVisible(find.byTooltip('自定义主题色'));
      await tester.tap(find.byTooltip('自定义主题色'));
      await tester.pumpAndSettle();
      expect(find.text('自定义主题色'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test('accent colors keep readable Material roles in all six variants', () {
    for (final preset in ThemePreset.values) {
      for (final brightness in Brightness.values) {
        for (final accent in [
          ...ThemePreset.accents.values,
          Colors.yellow,
          Colors.black,
          Colors.white,
        ]) {
          final theme = AppTheme.build(
            presetId: preset.id,
            brightness: brightness,
            accentColor: accent,
          );
          final scheme = theme.colorScheme;
          final x = scheme.primary.computeLuminance();
          final y = scheme.onPrimary.computeLuminance();
          final ratio = x > y
              ? (x + 0.05) / (y + 0.05)
              : (y + 0.05) / (x + 0.05);
          expect(ratio, greaterThanOrEqualTo(4.5));
          expect(scheme.surface, preset.palette(brightness).background);
        }
      }
    }
  });

  testWidgets(
    'confirming custom accent circles the palette icon until another choice',
    (tester) async {
      await openDialog(tester, (_) {});
      final custom = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '自定义主题色',
      );
      expect(tester.widget<IconButton>(custom).isSelected, false);
      await tester.tap(custom);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      final button = tester.widget<IconButton>(custom);
      expect(button.isSelected, true);
      final side = button.style!.side!.resolve({})!;
      expect(side.width, 2);
      expect(side.color.a, greaterThan(0));
      await tester.tap(find.byTooltip('绿色'));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(custom).isSelected, false);
      await tester.tap(find.text('默认'));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(custom).isSelected, false);
    },
  );
}
