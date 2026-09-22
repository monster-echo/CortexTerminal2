import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// 物理键盘修饰键回归（工具栏粘滞 CTRL/ALT 之外的硬件键盘路径）：
/// Ctrl+C 必须发出 ETX(0x03)，Alt+B 必须发出 ESC+b。
void main() {
  testWidgets('hardware ctrl+c sends ETX; alt+b sends ESC prefix',
      (tester) async {
    final terminal = Terminal();
    final outputs = <String>[];
    terminal.onOutput = outputs.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            // 常显光标：blink 光标的动画定时器会挂到测试收尾。
            cursorType: TerminalCursorType.block,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // 点终端获得焦点（对齐真实交互）。
    await tester.tap(find.byType(TerminalView));
    await tester.pump();

    HardwareKeyboard.instance.clearState();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    // 冲掉手势识别器（双击）定时器并卸载视图，避免定时器挂到测试收尾。
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(outputs[0].codeUnits, [0x03],
        reason: 'Ctrl+C must send ETX (0x03)');
    expect(outputs[1].codeUnits, [0x1b, 0x62],
        reason: 'Alt+B must send ESC+b');
  });
}
