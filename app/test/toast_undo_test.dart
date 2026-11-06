import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/ui/theme.dart';
import 'package:ttyfm/ui/widgets/async_view.dart';

void main() {
  testWidgets('undo toast: message, [annuler] in bold green, 5 s', (tester) async {
    var undone = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ttyTheme(Tty.mocha),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => toastUndo(context, '« néons » archivé.', () => undone++),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.duration, const Duration(seconds: 5));
    expect(bar.backgroundColor, Tty.mocha.surface);
    expect((bar.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(8));
    expect(find.text('« néons » archivé.'), findsOneWidget);
    final undo = tester.widget<Text>(find.text('[annuler]'));
    expect(undo.style!.color, Tty.mocha.green);
    expect(undo.style!.fontWeight, FontWeight.w700);
    expect(
      tester.getSize(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first).width,
      420,
    );

    await tester.tap(find.text('[annuler]'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.byType(SnackBar), findsNothing);
  });
}
