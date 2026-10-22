import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/l10n/app_strings.dart';
import 'package:pdm_viewer/app/theme/app_theme.dart';
import 'package:pdm_viewer/ui/widgets/support_author_dialog.dart';

void main() {
  testWidgets('payment codes load in compact light and dark dialogs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness: brightness),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSupportAuthorDialog(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('赞赏作者'), findsOneWidget);
      expect(find.text('支付宝'), findsOneWidget);
      expect(find.text('微信支付'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      for (final asset in ['assets/alipay.jpg', 'assets/wechat_pay.png']) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName == asset,
          ),
          findsOneWidget,
        );
        await tester.runAsync(() async {
          final bytes = await rootBundle.load(asset);
          final codec = await ui.instantiateImageCodec(
            bytes.buffer.asUint8List(),
          );
          final frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThan(0));
          frame.image.dispose();
          codec.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }
    const english = AppStrings(Locale('en'));
    expect(english.translate('赞赏作者'), 'Support the Author');
    expect(english.translate('支付宝'), 'Alipay');
    expect(english.translate('微信支付'), 'WeChat Pay');
  });
}
