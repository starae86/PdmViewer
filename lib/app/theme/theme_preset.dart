import 'package:flutter/material.dart';

@immutable
class ThemePalette {
  const ThemePalette({
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.foreground,
    required this.chrome,
    required this.selection,
  });

  final Color accent;
  final Color onAccent;
  final Color background;
  final Color foreground;
  final Color chrome;
  final Color selection;
}

@immutable
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.label,
    required this.light,
    required this.dark,
  });

  final String id;
  final String label;
  final ThemePalette light;
  final ThemePalette dark;

  ThemePalette palette(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static const defaultId = 'workbench';

  static const accents = <String, Color>{
    '蓝色': Color(0xFF1565C0),
    '紫色': Color(0xFF6750A4),
    '绿色': Color(0xFF2E7D54),
    '橙色': Color(0xFFB85C00),
    '粉色': Color(0xFFB83575),
    '红色': Color(0xFFB3261E),
  };

  // Cross-platform color interpretations, not native component libraries.
  static const values = [
    ThemePreset(
      id: 'workbench',
      label: '默认',
      light: ThemePalette(
        accent: Color(0xFF0068DA),
        onAccent: Color(0xFFFFFFFF),
        background: Color(0xFFFFFFFF),
        foreground: Color(0xFF1F242B),
        chrome: Color(0xFFEDF0F4),
        selection: Color(0xFFD3E8FA),
      ),
      dark: ThemePalette(
        accent: Color(0xFF0A84FF),
        onAccent: Color(0xFF000000),
        background: Color(0xFF202124),
        foreground: Color(0xFFF0F2F5),
        chrome: Color(0xFF30343A),
        selection: Color(0xFF304F6A),
      ),
    ),
    ThemePreset(
      id: 'material',
      label: 'Material Design',
      light: ThemePalette(
        accent: Color(0xFF6750A4),
        onAccent: Color(0xFFFFFFFF),
        background: Color(0xFFFFFBFE),
        foreground: Color(0xFF1D1B20),
        chrome: Color(0xFFEDE5F3),
        selection: Color(0xFFDFCEF7),
      ),
      dark: ThemePalette(
        accent: Color(0xFFD0BCFF),
        onAccent: Color(0xFF381E72),
        background: Color(0xFF1C1B1F),
        foreground: Color(0xFFF1ECF4),
        chrome: Color(0xFF2E2836),
        selection: Color(0xFF604494),
      ),
    ),
    ThemePreset(
      id: 'fluent',
      label: 'Fluent Design',
      light: ThemePalette(
        accent: Color(0xFF0067C0),
        onAccent: Color(0xFFFFFFFF),
        background: Color(0xFFFFFFFF),
        foreground: Color(0xFF1A1A1A),
        chrome: Color(0xFFEBEDF0),
        selection: Color(0xFFD1E7FA),
      ),
      dark: ThemePalette(
        accent: Color(0xFF60CDFF),
        onAccent: Color(0xFF003449),
        background: Color(0xFF202020),
        foreground: Color(0xFFFFFFFF),
        chrome: Color(0xFF303338),
        selection: Color(0xFF24536B),
      ),
    ),
    ThemePreset(
      id: 'macos',
      label: 'macOS',
      light: ThemePalette(
        accent: Color(0xFF0068DA),
        onAccent: Color(0xFFFFFFFF),
        background: Color(0xFFFFFFFF),
        foreground: Color(0xFF1D1D1F),
        chrome: Color(0xFFE9EBEE),
        selection: Color(0xFFCFE2FC),
      ),
      dark: ThemePalette(
        accent: Color(0xFF0A84FF),
        onAccent: Color(0xFF000000),
        background: Color(0xFF1E1E1E),
        foreground: Color(0xFFF5F5F7),
        chrome: Color(0xFF303238),
        selection: Color(0xFF254D79),
      ),
    ),
  ];

  static ThemePreset? find(String? id) =>
      values.where((preset) => preset.id == id).firstOrNull;
}
