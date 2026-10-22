import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pdm_viewer/app/state/theme_controller.dart';
import 'package:pdm_viewer/app/theme/app_theme.dart';
import 'package:pdm_viewer/app/theme/theme_preset.dart';
import 'package:pdm_viewer/app/theme/theme_contrast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('contrast persists and unrelated changes retain it', () async {
    final temp = await Directory.systemTemp.createTemp('pdm_contrast_test');
    addTearDown(() => temp.delete(recursive: true));
    final storagePath = path.join(temp.path, 'theme.json');
    final controller = ThemeController(storagePath: storagePath);
    addTearDown(controller.dispose);
    expect(controller.contrast, ThemeContrast.medium);
    await controller.setAppearance(
      seedColor: controller.seedColor,
      fontFamily: null,
      presetId: controller.presetId,
      contrast: ThemeContrast.high,
    );
    await controller.setSeedColor(Colors.teal);
    final restored = ThemeController(storagePath: storagePath);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.contrast, ThemeContrast.high);
  });

  test('a fresh configuration defaults to workbench blue', () async {
    final temp = await Directory.systemTemp.createTemp('pdm_workbench_theme');
    addTearDown(() => temp.delete(recursive: true));
    final controller = ThemeController(
      storagePath: path.join(temp.path, 'theme.json'),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.presetId, 'workbench');
    expect(controller.themeMode, ThemeMode.system);
    expect(controller.contrast, ThemeContrast.medium);
    expect(ThemePreset.find(controller.presetId)!.label, '默认');
    expect(controller.resolvedBackgroundColor, Colors.white);
    await controller.setAppearance(
      seedColor: controller.seedColor,
      fontFamily: null,
      presetId: controller.presetId,
      themeMode: ThemeMode.dark,
    );
    expect(controller.resolvedBackgroundColor, const Color(0xFF202124));
    final restored = ThemeController(
      storagePath: path.join(temp.path, 'theme.json'),
    );
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.presetId, 'workbench');
    expect(restored.themeMode, ThemeMode.dark);
  });

  test(
    'persists independent style and accent override and can restore default',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'pdm_accent_theme_test',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storagePath = path.join(temp.path, 'theme.json');
      final controller = ThemeController(storagePath: storagePath);
      addTearDown(controller.dispose);
      await controller.setAppearance(
        seedColor: AppTheme.defaultSeedColor,
        fontFamily: 'Arial',
        presetId: 'macos',
        themeMode: ThemeMode.system,
        accentColor: const Color(0xFF2E7D54),
      );
      final restored = ThemeController(storagePath: storagePath);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.presetId, 'macos');
      expect(restored.accentColor, const Color(0xFF2E7D54));
      expect(restored.themeMode, ThemeMode.system);
      expect(restored.fontFamily, 'Arial');
      await restored.setAppearance(
        seedColor: restored.seedColor,
        fontFamily: restored.fontFamily,
        presetId: 'macos',
        themeMode: ThemeMode.system,
      );
      final defaults = ThemeController(storagePath: storagePath);
      addTearDown(defaults.dispose);
      await defaults.initialize();
      expect(defaults.accentColor, isNull);
      expect(defaults.presetId, 'macos');
    },
  );

  test('persists and reloads selected theme color', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'pdm_viewer_theme_controller_test',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final storagePath = path.join(tempDir.path, 'theme.json');
    final firstController = ThemeController(storagePath: storagePath);
    await firstController.initialize();
    await firstController.setSeedColor(const Color(0xCC007ACC));

    final secondController = ThemeController(storagePath: storagePath);
    await secondController.initialize();

    expect(
      secondController.seedColor.toARGB32(),
      const Color(0xCC007ACC).toARGB32(),
    );
  });

  test('persists font with color and can restore the system default', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'pdm_theme_font_test',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final storagePath = path.join(tempDir.path, 'theme.json');
    final controller = ThemeController(storagePath: storagePath);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.fontFamily, isNull);

    await controller.setAppearance(
      seedColor: const Color(0xFF007ACC),
      fontFamily: 'Arial',
    );
    // Changing only the color must retain the chosen font.
    await controller.setSeedColor(const Color(0xFF008080));
    final restored = ThemeController(storagePath: storagePath);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.fontFamily, 'Arial');
    expect(restored.seedColor, const Color(0xFF008080));

    await restored.setAppearance(
      seedColor: restored.seedColor,
      fontFamily: null,
    );
    final systemDefault = ThemeController(storagePath: storagePath);
    addTearDown(systemDefault.dispose);
    await systemDefault.initialize();
    expect(systemDefault.fontFamily, isNull);
    expect(systemDefault.seedColor, restored.seedColor);
  });

  test('persists dark mode and custom surface colors', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'pdm_dark_theme_test',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final storagePath = path.join(tempDir.path, 'theme.json');
    final controller = ThemeController(storagePath: storagePath);
    addTearDown(controller.dispose);
    await controller.setAppearance(
      seedColor: Colors.blue,
      fontFamily: null,
      brightness: Brightness.dark,
      backgroundColor: const Color(0xFF242424),
      foregroundColor: const Color(0xFFF0F0F0),
    );
    await controller.setSeedColor(Colors.green);
    final restored = ThemeController(storagePath: storagePath);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.brightness, Brightness.dark);
    expect(restored.customBackgroundColor, const Color(0xFF242424));
    expect(restored.customForegroundColor, const Color(0xFFF0F0F0));
    expect(restored.seedColor.toARGB32(), Colors.green.toARGB32());

    await restored.setAppearance(
      seedColor: restored.seedColor,
      fontFamily: null,
      brightness: Brightness.light,
    );
    expect(restored.customBackgroundColor, isNull);
    expect(restored.customForegroundColor, isNull);
  });

  test('older theme files keep light mode and default surfaces', () async {
    final tempDir = await Directory.systemTemp.createTemp('pdm_old_theme_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File(path.join(tempDir.path, 'theme.json'));
    await file.writeAsString(
      '{"seedColorArgb":4278221516,"fontFamily":"Arial"}',
    );
    final controller = ThemeController(storagePath: file.path);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.brightness, Brightness.light);
    expect(controller.customBackgroundColor, isNull);
    expect(controller.customForegroundColor, isNull);
    expect(controller.presetId, isNull);
    expect(controller.fontFamily, 'Arial');
    expect(controller.contrast, ThemeContrast.medium);
  });

  test(
    'new installs use Material theme and preset persists with automatic appearance',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm_preset_theme_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final storagePath = path.join(tempDir.path, 'theme.json');
      final controller = ThemeController(storagePath: storagePath);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.presetId, ThemePreset.defaultId);
      await controller.setAppearance(
        seedColor: AppTheme.defaultSeedColor,
        fontFamily: 'Arial',
        themeMode: ThemeMode.system,
        presetId: 'fluent',
      );
      final restored = ThemeController(storagePath: storagePath);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.presetId, 'fluent');
      expect(restored.fontFamily, 'Arial');
      expect(restored.themeMode, ThemeMode.system);
      final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
      addTearDown(dispatcher.clearPlatformBrightnessTestValue);
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      expect(restored.resolvedBackgroundColor, const Color(0xFF202020));
      dispatcher.platformBrightnessTestValue = Brightness.light;
      expect(restored.resolvedBackgroundColor, const Color(0xFFFFFFFF));
      await restored.setSeedColor(Colors.teal);
      expect(restored.presetId, isNull);
      expect(restored.customBackgroundColor, const Color(0xFFFFFFFF));
      expect(restored.customForegroundColor, const Color(0xFF1A1A1A));
    },
  );

  test(
    'automatic mode persists and resolves current system brightness',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm_auto_theme_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final storagePath = path.join(tempDir.path, 'theme.json');
      final controller = ThemeController(storagePath: storagePath);
      addTearDown(controller.dispose);
      await controller.setAppearance(
        seedColor: Colors.blue,
        fontFamily: null,
        themeMode: ThemeMode.system,
      );
      await controller.setSeedColor(Colors.green);
      final restored = ThemeController(storagePath: storagePath);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.themeMode, ThemeMode.system);
      final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
      addTearDown(dispatcher.clearPlatformBrightnessTestValue);
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      expect(restored.brightness, Brightness.dark);
      dispatcher.platformBrightnessTestValue = Brightness.light;
      expect(restored.brightness, Brightness.light);
    },
  );
}
