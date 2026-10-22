import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/theme/app_theme.dart';
import 'package:pdm_viewer/ui/widgets/user_guide.dart';

void main() {
  Future<UserGuideController> showGuide(
    WidgetTester tester, {
    String style = 'material',
    Brightness brightness = Brightness.light,
    bool hasProjects = true,
    VoidCallback? onTargetTap,
    bool settle = true,
  }) async {
    final controller = UserGuideController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(presetId: style, brightness: brightness),
        home: UserGuideScope(
          controller: controller,
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    for (final target in UserGuideTarget.values)
                      UserGuideAnchor(
                        target: target,
                        child: TextButton(
                          onPressed: onTargetTap ?? () {},
                          child: Text('target-${target.name}'),
                        ),
                      ),
                  ],
                ),
                Positioned.fill(
                  child: UserGuideOverlay(
                    controller: controller,
                    hasProjects: hasProjects,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    unawaited(controller.start());
    if (settle) await tester.pumpAndSettle();
    return controller;
  }

  testWidgets(
    'each bubble highlights its real target and supports navigation',
    (tester) async {
      final guide = await showGuide(tester);
      for (var step = 0; step < 5; step++) {
        expect(find.text('${step + 1} / 5'), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const ValueKey('user-guide-highlight'))),
          tester
              .getRect(find.byKey(guide.keyFor(guide.target)))
              .inflate(4)
              .intersect(Offset.zero & tester.getSize(find.byType(Scaffold))),
        );
        if (step < 4) {
          await tester.tap(find.text('下一步'));
          await tester.pumpAndSettle();
        }
      }
      await tester.tap(find.text('上一步'));
      await tester.pumpAndSettle();
      expect(find.text('4 / 5'), findsOneWidget);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(guide.active, isFalse);
      expect(find.byKey(const ValueKey('user-guide-highlight')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('first opening waits for measured geometry before painting', (
    tester,
  ) async {
    final guide = await showGuide(tester, settle: false);
    for (var opening = 0; opening < 2; opening++) {
      await tester.pump();
      expect(find.text('1 / 5'), findsNothing);
      await tester.pump();
      expect(find.text('1 / 5'), findsOneWidget);
      final highlight = find.byKey(const ValueKey('user-guide-highlight'));
      expect(
        tester.getRect(highlight),
        tester
            .getRect(find.byKey(guide.keyFor(guide.target)))
            .inflate(4)
            .intersect(Offset.zero & tester.getSize(find.byType(Scaffold))),
      );
      final bubblePosition = tester.getTopLeft(find.text('1 / 5'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('1 / 5')), bubblePosition);
      guide.finish();
      await tester.pumpAndSettle();
      if (opening == 0) unawaited(guide.start());
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('step transitions keep the highlight visible on every frame', (
    tester,
  ) async {
    final guide = await showGuide(tester);
    for (var step = 1; step < UserGuideTarget.values.length; step++) {
      await tester.tap(find.text('下一步'));
      // Inspect the transition itself, before post-frame measurements settle.
      await tester.pump();
      expect(find.text('${step + 1} / 5'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('user-guide-highlight')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('user-guide-highlight'))),
        tester
            .getRect(find.byKey(guide.keyFor(guide.target)))
            .inflate(4)
            .intersect(Offset.zero & tester.getSize(find.byType(Scaffold))),
      );
    }
    await tester.tap(find.text('上一步'));
    await tester.pump();
    expect(find.byKey(const ValueKey('user-guide-highlight')), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('highlight remains clickable and other targets are blocked', (
    tester,
  ) async {
    var taps = 0;
    final guide = await showGuide(tester, onTargetTap: () => taps++);
    await tester.tap(find.text('target-createProject'));
    expect(taps, 1);
    final other = tester.getCenter(find.text('target-help'));
    await tester.tapAt(other);
    expect(taps, 1);
    final action = Completer<void>();
    final pending = guide.performAction(
      UserGuideTarget.createProject,
      () => action.future,
      shouldAdvance: () => true,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-guide-highlight')), findsNothing);
    action.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(guide.target, UserGuideTarget.importPdm);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty projects can skip without creating sample data', (
    tester,
  ) async {
    final guide = await showGuide(tester, hasProjects: false);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('跳过向导'));
    await tester.pumpAndSettle();
    expect(guide.active, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bubbles fit compact windows and track resizing in every theme', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final style in ['material', 'fluent', 'macos']) {
      for (final brightness in Brightness.values) {
        await tester.binding.setSurfaceSize(const Size(800, 500));
        await showGuide(tester, style: style, brightness: brightness);
        for (var step = 0; step < 4; step++) {
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('下一步'));
          await tester.pumpAndSettle();
        }
        await tester.binding.setSurfaceSize(const Size(1000, 700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('跳过向导'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
}
