import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../data/services/app_storage_directory.dart';

import '../theme/app_theme.dart';
import '../theme/theme_preset.dart';
import '../theme/theme_contrast.dart';

class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController({Color? seedColor, String? storagePath})
    : _seedColor = seedColor ?? AppTheme.defaultSeedColor,
      _presetId = seedColor == null ? ThemePreset.defaultId : null,
      _storagePath = storagePath {
    WidgetsBinding.instance.addObserver(this);
  }

  Color _seedColor;
  String? _presetId;
  String? _fontFamily;
  ThemeMode _themeMode = ThemeMode.system;
  ThemeContrast _contrast = ThemeContrast.medium;
  Color? _backgroundColor;
  Color? _foregroundColor;
  Color? _accentColor;
  Locale? _locale;
  final String? _storagePath;

  Color get seedColor => _seedColor;
  String? get presetId => _presetId;
  Color? get accentColor => _accentColor;
  Locale get locale => _locale ?? _systemLocale;
  Locale get _systemLocale => Locale(
    WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh'
        ? 'zh'
        : 'en',
  );

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_locale == null) notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Color get resolvedBackgroundColor =>
      _backgroundColor ??
      ThemePreset.find(_presetId)?.palette(brightness).background ??
      AppTheme.defaultBackground(brightness);
  String? get fontFamily => _fontFamily;
  ThemeMode get themeMode => _themeMode;
  ThemeContrast get contrast => _contrast;
  Brightness get brightness => switch (_themeMode) {
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.light => Brightness.light,
  };
  Color? get customBackgroundColor => _backgroundColor;
  Color? get customForegroundColor => _foregroundColor;

  Future<void> initialize() async {
    final file = await _resolveStorageFile();
    if (!file.existsSync()) {
      return;
    }

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final argb = decoded['seedColorArgb'];
      _locale = switch (decoded['languageCode']) {
        'zh' => const Locale('zh'),
        'en' => const Locale('en'),
        _ => null,
      };
      _contrast = ThemeContrast.fromName(decoded['contrast']);
      _presetId = ThemePreset.find(decoded['presetId'] as String?)?.id;
      _themeMode = switch (decoded['themeMode']) {
        'system' => ThemeMode.system,
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => switch (decoded['brightness']) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        },
      };
      _backgroundColor = _readColor(decoded['backgroundColorArgb']);
      _foregroundColor = _readColor(decoded['foregroundColorArgb']);
      _accentColor = _readColor(decoded['accentColorArgb']);
      final fontFamily = decoded['fontFamily'];
      if (fontFamily is String && fontFamily.trim().isNotEmpty) {
        _fontFamily = fontFamily.trim();
      }
      if (argb is int) {
        _seedColor = Color(argb);
      } else if (argb is String) {
        final parsed = int.tryParse(argb);
        if (parsed != null) {
          _seedColor = Color(parsed);
        }
      }
    } catch (_) {
      return;
    }
  }

  Future<void> setSeedColor(Color value) async {
    await setAppearance(
      seedColor: value,
      fontFamily: _fontFamily,
      themeMode: _themeMode,
      backgroundColor: _presetId == null
          ? _backgroundColor
          : resolvedBackgroundColor,
      foregroundColor:
          _foregroundColor ??
          ThemePreset.find(_presetId)?.palette(brightness).foreground,
    );
  }

  Future<void> setLocale(Locale value) async {
    if (!['zh', 'en'].contains(value.languageCode)) {
      throw ArgumentError.value(value, 'locale', 'Supported languages: zh, en');
    }
    final next = Locale(value.languageCode);
    if (_locale == next) return;
    final previous = _locale;
    _locale = next;
    try {
      await _persist();
    } catch (_) {
      _locale = previous;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> setAppearance({
    required Color seedColor,
    required String? fontFamily,
    Brightness? brightness,
    ThemeMode? themeMode,
    Color? backgroundColor,
    Color? foregroundColor,
    String? presetId,
    Color? accentColor,
    ThemeContrast? contrast,
  }) async {
    final nextContrast = contrast ?? _contrast;
    final nextMode =
        themeMode ??
        (brightness == null
            ? _themeMode
            : brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light);
    final normalizedFamily = fontFamily?.trim();
    final nextFamily = normalizedFamily == null || normalizedFamily.isEmpty
        ? null
        : normalizedFamily;
    final nextPreset = ThemePreset.find(presetId)?.id;
    if (_seedColor.toARGB32() == seedColor.toARGB32() &&
        _presetId == nextPreset &&
        _accentColor == accentColor &&
        _fontFamily == nextFamily &&
        _themeMode == nextMode &&
        _contrast == nextContrast &&
        _backgroundColor == backgroundColor &&
        _foregroundColor == foregroundColor) {
      return;
    }
    _seedColor = seedColor;
    _presetId = nextPreset;
    _accentColor = accentColor;
    _fontFamily = nextFamily;
    _themeMode = nextMode;
    _contrast = nextContrast;
    _backgroundColor = backgroundColor;
    _foregroundColor = foregroundColor;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final file = await _resolveStorageFile();
    final directory = file.parent;
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'seedColorArgb': _seedColor.toARGB32(),
        'languageCode': _locale?.languageCode,
        'presetId': _presetId,
        'accentColorArgb': _accentColor?.toARGB32(),
        'fontFamily': _fontFamily,
        'brightness': brightness.name,
        'themeMode': _themeMode.name,
        'contrast': _contrast.name,
        'backgroundColorArgb': _backgroundColor?.toARGB32(),
        'foregroundColorArgb': _foregroundColor?.toARGB32(),
      }),
    );
  }

  Future<File> _resolveStorageFile() async {
    if (_storagePath case final storagePath? when storagePath.isNotEmpty) {
      return File(storagePath);
    }

    final appDir = await AppStorageDirectory.resolve();
    return File(path.join(appDir.path, 'theme.json'));
  }

  static Color? _readColor(Object? value) {
    final argb = value is int ? value : int.tryParse('$value');
    return argb == null ? null : Color(argb);
  }
}
