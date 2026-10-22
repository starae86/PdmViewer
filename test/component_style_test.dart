import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/theme/app_theme.dart';
import 'package:pdm_viewer/app/theme/component_style.dart';
import 'package:pdm_viewer/app/theme/theme_preset.dart';

void main() {
  testWidgets('preview filter chips use themed text and distinct state fills', (
    tester,
  ) async {
    for (final preset in ThemePreset.values) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.build(
          presetId: preset.id,
          brightness: brightness,
          fontFamily: 'Test UI Font',
        );
        final scheme = theme.colorScheme;
        final profile = theme.extension<ComponentStyle>()!;
        final fills = <Color>[];
        for (final selected in [false, true]) {
          for (final enabled in [true, false]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: FilterChip(
                    label: const Text('生成 DDL'),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: enabled ? (_) {} : null,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final label = tester.element(find.text('生成 DDL'));
            final style = DefaultTextStyle.of(label).style;
            expect(style.fontFamily, 'Test UI Font');
            expect(style.fontSize, theme.textTheme.labelLarge!.fontSize);
            expect(style.fontWeight, theme.textTheme.labelLarge!.fontWeight);
            expect(
              style.color,
              !enabled
                  ? scheme.onSurface.withValues(alpha: 0.38)
                  : selected
                  ? profile.selectionForeground(scheme)
                  : scheme.onSurface,
            );
            final ink = tester.widget<Ink>(
              find
                  .descendant(
                    of: find.byType(FilterChip),
                    matching: find.byType(Ink),
                  )
                  .first,
            );
            final fill = (ink.decoration! as ShapeDecoration).color!;
            expect(
              fill,
              !enabled
                  ? scheme.onSurface.withValues(alpha: 0.12)
                  : selected
                  ? profile.selectionFill(scheme)
                  : scheme.surfaceContainerHigh,
            );
            if (enabled) fills.add(fill);
          }
        }
        expect(fills[0], isNot(fills[1]));
      }
    }
  });

  test('all presets retain readable text and distinct control boundaries', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
    }

    for (final preset in ThemePreset.values) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.build(
          presetId: preset.id,
          brightness: brightness,
        );
        final scheme = theme.colorScheme;
        expect(
          contrast(scheme.onSurfaceVariant, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.outline, scheme.surface),
          greaterThanOrEqualTo(3),
        );
        expect(
          contrast(scheme.surfaceContainerLow, scheme.surface),
          greaterThan(1.1),
        );
        final profile = theme.extension<ComponentStyle>()!;
        expect(
          contrast(
            profile.selectionForeground(scheme),
            profile.selectionFill(scheme),
          ),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  test('workbench keeps surfaces neutral and actions visually distinct', () {
    for (final brightness in Brightness.values) {
      final theme = AppTheme.build(
        presetId: 'workbench',
        brightness: brightness,
      );
      final scheme = theme.colorScheme;
      final palette = ThemePreset.find('workbench')!.palette(brightness);
      expect(scheme.surface, palette.background);
      expect(scheme.surfaceContainerLow, palette.chrome);
      expect(scheme.secondaryContainer, palette.selection);
      expect(scheme.onSecondaryContainer, palette.foreground);
      expect(
        theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
        palette.accent,
      );
      expect(
        theme.outlinedButtonTheme.style!.backgroundColor!.resolve({}),
        palette.chrome,
      );
      expect(
        theme.outlinedButtonTheme.style!.foregroundColor!.resolve({}),
        palette.accent,
      );
      final custom = AppTheme.build(
        presetId: 'workbench',
        brightness: brightness,
        accentColor: Colors.green,
      );
      expect(custom.colorScheme.surface, scheme.surface);
      expect(
        custom.colorScheme.surfaceContainerLow,
        scheme.surfaceContainerLow,
      );
    }
  });

  test('labels and filled buttons use global theme color roles', () {
    for (final preset in ThemePreset.values) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.build(
          presetId: preset.id,
          brightness: brightness,
          accentColor: Colors.teal,
        );
        for (final label in [
          theme.textTheme.labelLarge,
          theme.textTheme.labelMedium,
          theme.textTheme.labelSmall,
        ]) {
          expect(label?.color, theme.textTheme.bodyMedium?.color);
        }
        final button = theme.filledButtonTheme.style!;
        final scheme = theme.colorScheme;
        expect(button.backgroundColor!.resolve({}), scheme.primary);
        expect(button.foregroundColor!.resolve({}), scheme.onPrimary);
        expect(
          button.foregroundColor!.resolve({WidgetState.disabled}),
          scheme.onSurface.withValues(alpha: 0.38),
        );
      }
    }
  });

  test('all text roles and component labels share the configured font', () {
    for (final preset in ThemePreset.values) {
      final theme = AppTheme.build(
        presetId: preset.id,
        fontFamily: 'Test UI Font',
      );
      for (final text in [theme.textTheme, theme.primaryTextTheme]) {
        for (final style in [
          text.displayLarge,
          text.displayMedium,
          text.displaySmall,
          text.headlineLarge,
          text.headlineMedium,
          text.headlineSmall,
          text.titleLarge,
          text.titleMedium,
          text.titleSmall,
          text.bodyLarge,
          text.bodyMedium,
          text.bodySmall,
          text.labelLarge,
          text.labelMedium,
          text.labelSmall,
        ]) {
          expect(style?.fontFamily, 'Test UI Font');
          expect(style?.fontFamilyFallback, isNotEmpty);
        }
      }
      expect(theme.textTheme.bodyMedium?.fontWeight, FontWeight.w400);
      expect(
        WidgetStateProperty.resolveAs<TextStyle>(
          theme.chipTheme.labelStyle!,
          {},
        ).fontFamily,
        'Test UI Font',
      );
    }
  });

  test('profiles change component geometry, not only palette', () {
    final themes = [
      for (final preset in ThemePreset.values)
        AppTheme.build(presetId: preset.id),
    ];
    expect(
      themes.map((t) => t.extension<ComponentStyle>()!.buttonRadius).toSet(),
      {100, 4, 5, 6},
    );
    expect(
      themes.map((t) => t.extension<ComponentStyle>()!.controlHeight).toSet(),
      {36, 32, 28},
    );
    expect(themes.map((t) => t.dialogTheme.elevation).toSet(), {0, 12, 16});
    for (final theme in themes) {
      final profile = theme.extension<ComponentStyle>()!;
      final button = theme.filledButtonTheme.style!;
      final shape = button.shape!.resolve({})! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(profile.buttonRadius));
      expect(button.minimumSize!.resolve({})!.height, profile.controlHeight);
      expect(
        (theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder)
            .borderRadius,
        profile.controlBorderRadius,
      );
      expect(
        theme.inputDecorationTheme.focusedBorder!.borderSide.width,
        profile.focusWidth,
      );
      expect(
        (theme.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(profile.dialogRadius),
      );
      expect(
        theme.splashFactory,
        profile.isMaterial ? InkRipple.splashFactory : NoSplash.splashFactory,
      );
    }
  });

  test('all profiles retain geometry with dark mode and custom accent', () {
    for (final preset in ThemePreset.values) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.build(
          presetId: preset.id,
          brightness: brightness,
          accentColor: Colors.teal,
        );
        final profile = theme.extension<ComponentStyle>()!;
        expect(profile, same(ComponentStyle.forPreset(preset.id)));
        final scheme = theme.colorScheme;
        final menu = theme.menuButtonTheme.style!;
        expect(
          menu.foregroundColor!.resolve({WidgetState.disabled}),
          scheme.onSurface.withValues(alpha: 0.38),
        );
        expect(
          profile.selectionForeground(scheme),
          profile.isMacos
              ? scheme.onPrimary
              : profile.isMaterial
              ? scheme.onSecondaryContainer
              : scheme.onSurface,
        );
        final indicator = profile.tabIndicator(scheme).border! as Border;
        expect(indicator.top.width, profile.isFluent ? 2 : 0);
        expect(
          indicator.bottom.width,
          profile.isMaterial
              ? 2
              : profile.isMacos
              ? 1
              : 0,
        );
      }
    }
    expect(ComponentStyle.forPreset(null), same(ComponentStyle.material));
    expect(
      AppTheme.build().extension<ComponentStyle>(),
      same(ComponentStyle.material),
    );
  });

  testWidgets('switching styles preserves input and selection', (tester) async {
    final text = TextEditingController(text: 'CUSTOMER');
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    var selected = 0;
    for (final preset in ThemePreset.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(presetId: preset.id),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  TextField(controller: text, focusNode: focus),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('字段')),
                      ButtonSegment(value: 1, label: Text('DDL')),
                    ],
                    selected: {selected},
                    onSelectionChanged: (value) =>
                        setState(() => selected = value.first),
                  ),
                  FilledButton(onPressed: () {}, child: const Text('保存')),
                  OutlinedButton(onPressed: () {}, child: const Text('取消')),
                  FilterChip(
                    label: const Text('注释'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: 'oracle',
                    borderRadius: AppTheme.menuRadiusOf(context),
                    items: const [
                      DropdownMenuItem(value: 'oracle', child: Text('Oracle')),
                    ],
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('DDL'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(text.text, 'CUSTOMER');
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
