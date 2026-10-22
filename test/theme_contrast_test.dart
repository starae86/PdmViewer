import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/theme/app_theme.dart';
import 'package:pdm_viewer/app/theme/component_style.dart';
import 'package:pdm_viewer/app/theme/theme_contrast.dart';
import 'package:pdm_viewer/app/theme/theme_preset.dart';

double contrastRatio(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
}

void main() {
  test('medium contrast preserves chosen accents across styles and modes', () {
    for (final preset in ThemePreset.values) {
      for (final brightness in Brightness.values) {
        for (final accent in [
          ...ThemePreset.accents.values,
          const Color(0xFF12A5B8),
        ]) {
          final theme = AppTheme.build(
            presetId: preset.id,
            brightness: brightness,
            accentColor: accent,
          );
          expect(theme.colorScheme.primary, accent);
          expect(
            theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
            accent,
          );
          expect(
            theme.textButtonTheme.style!.foregroundColor!.resolve({}),
            accent,
          );
          expect(
            theme.outlinedButtonTheme.style!.foregroundColor!.resolve({}),
            accent,
          );
          expect(
            contrastRatio(
              theme.colorScheme.primary,
              theme.colorScheme.onPrimary,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    }
    const legacyAccent = Color(0xFF1565C0);
    expect(
      AppTheme.build(seedColor: legacyAccent).colorScheme.primary,
      legacyAccent,
    );
  });

  test('default and macOS themes share accent text colors', () {
    for (final brightness in Brightness.values) {
      final workbench = AppTheme.build(
        presetId: 'workbench',
        brightness: brightness,
      );
      final macos = AppTheme.build(presetId: 'macos', brightness: brightness);
      expect(workbench.colorScheme.primary, macos.colorScheme.primary);
      expect(
        workbench.textButtonTheme.style!.foregroundColor!.resolve({}),
        macos.textButtonTheme.style!.foregroundColor!.resolve({}),
      );
      expect(
        workbench.outlinedButtonTheme.style!.foregroundColor!.resolve({}),
        macos.outlinedButtonTheme.style!.foregroundColor!.resolve({}),
      );
    }
  });

  test(
    'custom accents still respond to contrast and derive supporting tones',
    () {
      for (final preset in ThemePreset.values) {
        for (final brightness in Brightness.values) {
          final themes = [
            for (final level in ThemeContrast.values)
              AppTheme.build(
                presetId: preset.id,
                brightness: brightness,
                accentColor: const Color(0xFF1565C0),
                contrast: level,
              ),
          ];
          final medium = themes[1].colorScheme;
          expect(medium.primary, const Color(0xFF1565C0));
          expect(medium.primaryContainer, isNot(medium.primary));
          expect(medium.secondaryContainer, isNot(medium.primary));
          for (final theme in [themes.first, themes.last]) {
            expect(theme.colorScheme.primary, isNot(medium.primary));
            expect(
              contrastRatio(
                theme.colorScheme.primary,
                theme.colorScheme.onPrimary,
              ),
              greaterThanOrEqualTo(4.5),
            );
          }
        }
      }
    },
  );

  testWidgets('Material menu and sidebar follow accent and contrast together', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final level in ThemeContrast.values) {
        final blue = AppTheme.build(
          presetId: 'material',
          brightness: brightness,
          contrast: level,
          accentColor: Colors.blue,
        );
        final green = AppTheme.build(
          presetId: 'material',
          brightness: brightness,
          contrast: level,
          accentColor: Colors.green,
        );
        expect(
          blue.colorScheme.surfaceContainerLow,
          isNot(green.colorScheme.surfaceContainerLow),
        );
        expect(
          blue.colorScheme.secondaryContainer,
          isNot(green.colorScheme.secondaryContainer),
        );
        await tester.pumpWidget(
          MaterialApp(
            themeAnimationDuration: Duration.zero,
            theme: green,
            darkTheme: green,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: Builder(
              builder: (context) {
                expect(
                  AppTheme.menuStripFill(context),
                  green.colorScheme.surfaceContainerLow,
                );
                expect(
                  AppTheme.tabStripFill(context),
                  green.colorScheme.surfaceContainerLow,
                );
                expect(
                  AppTheme.treeSelectionFill(context),
                  green.colorScheme.secondaryContainer,
                );
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
    }
  });

  test('missing or invalid stored levels default to medium', () {
    expect(ThemeContrast.fromName(null), ThemeContrast.medium);
    expect(ThemeContrast.fromName('invalid'), ThemeContrast.medium);
    expect(ThemeContrast.fromName('high'), ThemeContrast.high);
  });

  test(
    'custom accents stay readable and support custom middle-tone surfaces',
    () {
      for (final brightness in Brightness.values) {
        for (final level in ThemeContrast.values) {
          for (final accent in [
            Colors.yellow,
            Colors.black,
            Colors.white,
            Colors.teal,
          ]) {
            final theme = AppTheme.build(
              presetId: 'workbench',
              brightness: brightness,
              contrast: level,
              accentColor: accent,
            );
            expect(
              contrastRatio(
                theme.colorScheme.primary,
                theme.colorScheme.onPrimary,
              ),
              greaterThanOrEqualTo(4.5),
            );
          }
          final custom = AppTheme.build(
            presetId: 'workbench',
            brightness: brightness,
            contrast: level,
            backgroundColor: const Color(0xFF808080),
          );
          expect(
            contrastRatio(
              custom.colorScheme.primary,
              custom.colorScheme.onPrimary,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );

  test(
    'levels increase contrast and adapt the accent without changing style',
    () {
      for (final preset in ThemePreset.values) {
        for (final brightness in Brightness.values) {
          final themes = [
            for (final level in ThemeContrast.values)
              AppTheme.build(
                presetId: preset.id,
                brightness: brightness,
                contrast: level,
              ),
          ];
          for (var i = 0; i < themes.length; i++) {
            final theme = themes[i];
            final scheme = theme.colorScheme;
            final profile = theme.extension<ComponentStyle>()!;
            expect(profile, same(ComponentStyle.forPreset(preset.id)));
            expect(
              theme.extension<ContrastStyle>()!.level,
              ThemeContrast.values[i],
            );
            expect(
              contrastRatio(scheme.primary, scheme.onPrimary),
              greaterThanOrEqualTo(4.5),
            );
            expect(scheme.surface, themes[1].colorScheme.surface);
            expect(
              contrastRatio(scheme.onSurfaceVariant, scheme.surface),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              contrastRatio(
                profile.selectionForeground(scheme),
                profile.selectionFill(scheme),
              ),
              greaterThanOrEqualTo(4.5),
            );
            if (i > 0) {
              final previous = themes[i - 1].colorScheme;
              expect(
                contrastRatio(scheme.primary, scheme.surface),
                greaterThan(contrastRatio(previous.primary, previous.surface)),
              );
              expect(
                contrastRatio(scheme.outline, scheme.surface),
                greaterThan(contrastRatio(previous.outline, previous.surface)),
              );
              expect(
                contrastRatio(scheme.surfaceContainerLow, scheme.surface),
                greaterThan(
                  contrastRatio(previous.surfaceContainerLow, previous.surface),
                ),
              );
              expect(
                contrastRatio(scheme.onSurfaceVariant, scheme.surface),
                greaterThan(
                  contrastRatio(previous.onSurfaceVariant, previous.surface),
                ),
              );
            }
          }
        }
      }
    },
  );

  testWidgets('table and search colors use shared contrast tokens', (
    tester,
  ) async {
    for (final level in ThemeContrast.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(presetId: 'workbench', contrast: level),
          home: Builder(
            builder: (context) {
              final tokens = ContrastStyle.of(context);
              final scheme = Theme.of(context).colorScheme;
              expect(
                AppTheme.selectionFill(context),
                Color.alphaBlend(
                  scheme.primary.withValues(
                    alpha: tokens.selectionAlpha(Brightness.light),
                  ),
                  scheme.surface,
                ),
              );
              expect(
                AppTheme.searchHighlight(context, active: true),
                Color.alphaBlend(
                  scheme.primary.withValues(alpha: tokens.activeMatchOpacity),
                  scheme.surface,
                ),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
  });
}
