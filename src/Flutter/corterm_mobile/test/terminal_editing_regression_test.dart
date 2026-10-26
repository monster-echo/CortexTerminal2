import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';
import 'package:xterm/xterm.dart';

void main() {
  final edits = <String>[];
  var deletes = 0;
  late GlobalKey<CustomTextEditState> key;
  late FocusNode focus;
  Future<void> mount(WidgetTester tester, {bool detection = false}) async {
    key = GlobalKey<CustomTextEditState>();
    focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CustomTextEdit(
          key: key,
          focusNode: focus,
          autofocus: true,
          deleteDetection: detection,
          onInsert: edits.add,
          onDelete: () => deletes++,
          onComposing: (_) {},
          onAction: (_) {},
          onKeyEvent: (_, event) => event.logicalKey == LogicalKeyboardKey.enter
              ? KeyEventResult.handled
              : KeyEventResult.ignored,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
  }

  void update(String text, {TextRange composing = TextRange.empty}) =>
      key.currentState!.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: composing,
        ),
      );
  setUp(() {
    edits.clear();
    deletes = 0;
  });
  testWidgets('cumulative platform updates emit each character exactly once', (
    tester,
  ) async {
    await mount(tester);
    for (final text in ['p', 'pr', 'pri', 'prin', 'print', 'printf']) {
      update(text);
    }
    expect(edits.join(), 'printf');
  });
  testWidgets('duplicate platform values do not re-send committed text', (
    tester,
  ) async {
    await mount(tester);
    update('hello');
    update('hello');
    expect(edits.join(), 'hello');
  });
  testWidgets('Chinese composition emits committed characters only', (
    tester,
  ) async {
    await mount(tester);
    update('n', composing: const TextRange(start: 0, end: 1));
    update('ni', composing: const TextRange(start: 0, end: 2));
    expect(edits, isEmpty);
    update('你');
    update('你好');
    expect(edits.join(), '你好');
  });
  testWidgets('paste followed by typing does not repeat pasted commands', (
    tester,
  ) async {
    await mount(tester);
    update('echo one\necho two');
    update('echo one\necho two!');
    expect(edits.join(), 'echo one\necho two!');
  });
  testWidgets('backspace deletes once for each removed character', (
    tester,
  ) async {
    await mount(tester);
    update('abc');
    update('ab');
    update('a');
    expect(edits.join(), 'abc');
    expect(deletes, 2);
  });
  testWidgets('delete sentinel supports repeated backspace at empty input', (
    tester,
  ) async {
    await mount(tester, detection: true);
    update(' ');
    update(' ');
    expect(deletes, 2);
    expect(edits, isEmpty);
  });
  testWidgets('emoji backspace is one deletion, not two surrogate deletions', (
    tester,
  ) async {
    await mount(tester);
    update('a😀');
    update('a');
    expect(deletes, 1);
    expect(edits.join(), 'a😀');
  });
  testWidgets('cancelled IME composition does not send unfinished text', (
    tester,
  ) async {
    await mount(tester);
    update('ready');
    update('ready ni', composing: const TextRange(start: 5, end: 8));
    update('ready');
    expect(edits.join(), 'ready');
    expect(deletes, 0);
  });
  testWidgets(
    'TerminalView emits a cumulative command exactly once, then Enter',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal()..onOutput = output.add;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              autofocus: true,
              deleteDetection: true,
            ),
          ),
        ),
      );
      await tester.pump();
      const command = "printf 'CORTERM_UX_REGRESSION_OK\\n'";
      for (var index = 1; index <= command.length; index++) {
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: '  ${command.substring(0, index)}',
            selection: TextSelection.collapsed(offset: index + 2),
          ),
        );
        await tester.pump();
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(output.join(), '$command\r');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(output.last, '\x15');
    },
  );
  testWidgets('hardware enter resets the local editing buffer', (tester) async {
    await mount(tester);
    update('old');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    update('x');
    expect(edits.join(), 'oldx');
    expect(deletes, 0);
  });
}
