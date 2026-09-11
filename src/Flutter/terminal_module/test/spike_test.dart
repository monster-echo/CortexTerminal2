import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('terminal echo works', () {
    final terminal = Terminal();
    terminal.write('hello\r\n');
    expect(terminal.buffer.getText(), contains('hello'));
  });
}
