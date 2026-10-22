import 'package:flutter/material.dart';
import '../../app/l10n/app_strings.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/theme_preset.dart';
import '../../app/theme/theme_contrast.dart';
import '../../data/services/system_font_service.dart';

@immutable
class ThemeSettingsSelection {
  const ThemeSettingsSelection({
    required this.seedColor,
    this.brightness = Brightness.light,
    ThemeMode? themeMode,
    this.backgroundColor,
    this.foregroundColor,
    this.fontFamily,
    this.presetId,
    this.accentColor,
    this.contrast = ThemeContrast.medium,
  }) : themeMode =
           themeMode ??
           (brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.system);

  final Color seedColor;
  final Brightness brightness;
  final ThemeMode themeMode;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final String? fontFamily;
  final String? presetId;
  final Color? accentColor;
  final ThemeContrast contrast;
}

class ThemeSettingsDialog extends StatefulWidget {
  const ThemeSettingsDialog({super.key, required this.initial});
  final ThemeSettingsSelection initial;

  @override
  State<ThemeSettingsDialog> createState() => _ThemeSettingsDialogState();
}

class _ThemeSettingsDialogState extends State<ThemeSettingsDialog> {
  late ThemeMode _themeMode;
  late ThemeContrast _contrast;
  late String _presetId;
  Color? _accentColor;
  bool _usingCustomAccent = false;
  String? _fontFamily;
  List<String> _fonts = const [];
  bool _loadingFonts = true;
  String? _fontError;

  Brightness get _brightness => switch (_themeMode) {
    ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    ThemeMode.dark => Brightness.dark,
    ThemeMode.light => Brightness.light,
  };
  ThemePreset get _preset => ThemePreset.find(_presetId)!;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initial.themeMode;
    _contrast = widget.initial.contrast;
    _fontFamily = widget.initial.fontFamily;
    _accentColor = widget.initial.accentColor;
    _usingCustomAccent =
        _accentColor != null &&
        !ThemePreset.accents.values.contains(_accentColor);
    _presetId =
        ThemePreset.find(widget.initial.presetId)?.id ?? ThemePreset.defaultId;
    _loadFonts();
  }

  Future<void> _pickAccentColor(BuildContext context) async {
    var color = _accentColor ?? _preset.palette(_brightness).accent;
    final selected = await showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const LText('自定义主题色'),
          content: SizedBox(
            width: 280,
            child: SingleChildScrollView(
              child: ColorPicker(
                pickerColor: color,
                onColorChanged: (value) => update(() => color = value),
                enableAlpha: false,
                portraitOnly: true,
                colorPickerWidth: 260,
                pickerAreaHeightPercent: 0.6,
                hexInputBar: true,
                labelTypes: const [ColorLabelType.rgb],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const LText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, color),
              child: const LText('确认'),
            ),
          ],
        ),
      ),
    );
    if (mounted && selected != null) {
      setState(() {
        _accentColor = selected;
        _usingCustomAccent = true;
      });
    }
  }

  void _resetAppearance() {
    setState(() {
      _presetId = ThemePreset.defaultId;
      _themeMode = ThemeMode.system;
      _contrast = ThemeContrast.medium;
      _accentColor = null;
      _usingCustomAccent = false;
      _fontFamily = null;
    });
  }

  Future<void> _loadFonts() async {
    try {
      final fonts = await SystemFontService.loadFamilies();
      if (!mounted) return;
      setState(() {
        _fonts = fonts;
        _loadingFonts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingFonts = false;
        _fontError = '无法读取系统字体，可继续使用系统默认字体。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.build(
        contrast: _contrast,
        presetId: _presetId,
        accentColor: _accentColor,
        brightness: _brightness,
        fontFamily: _fontFamily,
      ),
      child: Builder(
        builder: (context) {
          final fonts = {..._fonts, ?_fontFamily};
          return AlertDialog(
            title: const LText('主题'),
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            content: SizedBox(
              width: 520,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height - 190).clamp(
                    120.0,
                    600.0,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(
                        '界面风格',
                        DropdownButtonFormField<String>(
                          borderRadius: AppTheme.menuRadiusOf(context),
                          initialValue: _presetId,
                          isExpanded: true,
                          decoration: _decoration,
                          items: [
                            for (final preset in ThemePreset.values)
                              DropdownMenuItem(
                                value: preset.id,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: preset
                                            .palette(_brightness)
                                            .accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        context.tr(preset.label),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _presetId = value);
                            }
                          },
                        ),
                      ),
                      const Divider(height: 1),
                      _row(
                        '模式',
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _modeOption(
                              context,
                              ThemeMode.system,
                              '自动',
                              Icons.brightness_auto_outlined,
                            ),
                            const SizedBox(width: 8),
                            _modeOption(
                              context,
                              ThemeMode.light,
                              '浅色',
                              Icons.light_mode_outlined,
                            ),
                            const SizedBox(width: 8),
                            _modeOption(
                              context,
                              ThemeMode.dark,
                              '深色',
                              Icons.dark_mode_outlined,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      _row(
                        '对比度',
                        Align(
                          alignment: Alignment.centerRight,
                          child: SegmentedButton<ThemeContrast>(
                            showSelectedIcon: false,
                            segments: [
                              for (final level in ThemeContrast.values)
                                ButtonSegment(
                                  value: level,
                                  label: LText(level.label),
                                ),
                            ],
                            selected: {_contrast},
                            onSelectionChanged: (values) =>
                                setState(() => _contrast = values.first),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      _row(
                        '主题色',
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                backgroundColor: _accentColor == null
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : null,
                                foregroundColor: _accentColor == null
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer
                                    : null,
                              ),
                              onPressed: () => setState(() {
                                _accentColor = null;
                                _usingCustomAccent = false;
                              }),
                              child: const LText('默认'),
                            ),
                            for (final entry in ThemePreset.accents.entries)
                              _accentOption(context, entry.key, entry.value),
                            IconButton(
                              tooltip: context.tr('自定义主题色'),
                              isSelected: _usingCustomAccent,
                              style: IconButton.styleFrom(
                                shape: const CircleBorder(),
                                side: BorderSide(
                                  color: _usingCustomAccent
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                                backgroundColor: _usingCustomAccent
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : Colors.transparent,
                              ),
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 32,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () => _pickAccentColor(context),
                              icon: const Icon(
                                Icons.palette_outlined,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      _row(
                        '字体',
                        DropdownButtonFormField<String>(
                          borderRadius: AppTheme.menuRadiusOf(context),
                          initialValue: _fontFamily ?? '',
                          isExpanded: true,
                          menuMaxHeight: 220,
                          decoration: _decoration,
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: LText('系统默认'),
                            ),
                            for (final family in fonts)
                              DropdownMenuItem(
                                value: family,
                                child: Text(
                                  family,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _fontFamily = value == '' ? null : value,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      if (_loadingFonts || _fontError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: LText(
                            _loadingFonts ? '正在读取系统字体...' : _fontError!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 12),
                      const LText('字体预览：表结构 PDM Viewer 0123456789'),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: _resetAppearance, child: const LText('重置')),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const LText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  ThemeSettingsSelection(
                    contrast: _contrast,
                    seedColor:
                        _accentColor ?? _preset.palette(_brightness).accent,
                    accentColor: _accentColor,
                    presetId: _presetId,
                    brightness: _brightness,
                    themeMode: _themeMode,
                    fontFamily: _fontFamily,
                  ),
                ),
                child: const LText('应用'),
              ),
            ],
          );
        },
      ),
    );
  }

  static const _decoration = InputDecoration(
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  );

  Widget _accentOption(BuildContext context, String label, Color color) {
    final selected = !_usingCustomAccent && _accentColor == color;
    return Semantics(
      button: true,
      selected: selected,
      label: context.tr(label),
      child: Tooltip(
        message: context.tr(label),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() {
            _accentColor = color;
            _usingCustomAccent = false;
          }),
          child: Container(
            width: 28,
            height: 28,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, Widget option) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        SizedBox(width: 72, child: LText(label)),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: 340, child: option),
          ),
        ),
      ],
    ),
  );

  Widget _modeOption(
    BuildContext context,
    ThemeMode mode,
    String label,
    IconData icon,
  ) {
    final selected = _themeMode == mode;
    final brightness = switch (mode) {
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
    };
    final palette = _preset.palette(brightness);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: AppTheme.controlRadiusOf(context),
        onTap: () => setState(() => _themeMode = mode),
        child: Container(
          width: 94,
          height: 44,
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: AppTheme.controlRadiusOf(context),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: palette.foreground, size: 17),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: LText(
                    label,
                    style: TextStyle(color: palette.foreground),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
