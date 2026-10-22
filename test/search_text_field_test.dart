import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/ui/widgets/search_text_field.dart';

void main() {
  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    testWidgets('search input owns select-all with $modifier', (tester) async {
      final controller = TextEditingController(text: 'CUSTOMER_ID');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var tableSelectAll = 0;
      String? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.keyA,
                  control: true,
                ): () =>
                    tableSelectAll++,
                const SingleActivator(
                  LogicalKeyboardKey.keyA,
                  meta: true,
                ): () =>
                    tableSelectAll++,
              },
              child: SearchTextField(
                controller: controller,
                focusNode: focus,
                onChanged: (value) => changed = value,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(modifier);
      expect(tableSelectAll, 0);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 11),
      );
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(changed, '');
      expect(find.byTooltip('清空搜索'), findsNothing);
      await tester.enterText(find.byType(TextField), 'new query');
      await tester.pump();
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(changed, '');
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'search activity avoids flashing and stays visible for slow queries',
    (tester) async {
      Future<void> show(bool searching) => tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 40,
            height: 40,
            child: SearchActivityIndicator(searching: searching),
          ),
        ),
      );
      await show(true);
      await tester.pump(const Duration(milliseconds: 100));
      await show(false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await show(true);
      await tester.pump(const Duration(milliseconds: 201));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await show(false);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 151));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
