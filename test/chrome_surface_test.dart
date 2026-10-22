import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/theme/app_theme.dart';
import 'package:pdm_viewer/ui/widgets/chrome_surface.dart';

void main() {
  testWidgets('chrome stays opaque and interactive in every profile', (
    tester,
  ) async {
    for (final style in ['material', 'fluent', 'macos']) {
      for (final highContrast in [false, true]) {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(presetId: style),
            home: MediaQuery(
              data: MediaQueryData(highContrast: highContrast),
              child: Scaffold(
                body: ChromeSurface(
                  child: SizedBox(
                    width: 240,
                    height: 400,
                    child: TextButton(
                      onPressed: () => taps++,
                      child: const Text('项目'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(ChromeSurface),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(
          decoration.color,
          AppTheme.menuStripFill(tester.element(find.byType(ChromeSurface))),
        );
        expect(decoration.color!.a, 1);
        await tester.tap(find.text('项目'));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'search highlights derive from the current accent in both appearances',
    (tester) async {
      for (final style in ['material', 'fluent', 'macos']) {
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(
                presetId: style,
                brightness: brightness,
                accentColor: Colors.teal,
              ),
              home: Builder(
                builder: (context) {
                  final scheme = Theme.of(context).colorScheme;
                  expect(
                    AppTheme.searchHighlight(context),
                    Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.12),
                      scheme.surface,
                    ),
                  );
                  expect(
                    AppTheme.searchHighlight(context, active: true),
                    Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.30),
                      scheme.surface,
                    ),
                  );
                  expect(
                    AppTheme.searchHighlight(context),
                    isNot(AppTheme.searchHighlight(context, active: true)),
                  );
                  return const SizedBox();
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
