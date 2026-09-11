
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// M0 spike：最小 TerminalView 回显 + MethodChannel ping-pong + 二进制写入。
///
/// 验证目标（G1-G6）：渲染、软键盘、通道、手势、等宽字体。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpikeApp());
}

const _controlChannel = MethodChannel('cortexterminal/terminal_control');
final _outputChannel = BasicMessageChannel<ByteData>(
  'cortexterminal/pty_output',
  BinaryCodec(),
);

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: SpikeScreen(),
    );
  }
}

class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  late final Terminal terminal;
  final controller = TerminalController();
  String _lastEvent = 'none';

  @override
  void initState() {
    super.initState();
    terminal = Terminal(
      maxLines: 64000,
      onOutput: (data) => terminal.write(data), // 本地回显（G2 验证 IME）
      onResize: (width, height, pixelWidth, pixelHeight) {
        setState(() => _lastEvent = 'resize $width x $height');
      },
    );
    terminal.write('CortexTerminal Flutter spike\r\n');
    terminal.write('localecho: type to test IME (G2)\r\n');
    terminal.write('monospace check (G6):\r\n');
    terminal.write('|-byw@  |-byw@  |-byw@ |\r\n');
    terminal.write('| MMMMM | mmmmm | lllii |\r\n');
    terminal.write('| 12345 | 67890 | 00000 |\r\n');
    // 长滚动内容（G5 翻页验证）
    for (var i = 1; i <= 300; i++) {
      terminal.write('scrollback line $i\r\n');
    }

    _controlChannel.setMethodCallHandler((call) async {
      setState(() => _lastEvent = 'ctrl:${call.method}');
      switch (call.method) {
        case 'ping':
          return 'pong';
        case 'write':
          final bytes = call.arguments as Uint8List;
          terminal.write(String.fromCharCodes(bytes));
          return null;
        default:
          throw MissingPluginException('unknown method ${call.method}');
      }
    });
    _outputChannel.setMessageHandler((data) async {
      if (data != null && data.lengthInBytes > 0) {
        terminal.write(String.fromCharCodes(data.buffer.asUint8List()));
      }
      return ByteData(0);
    });
    // 主动上报就绪（协议同 M1：onReady 由 Dart 在 channel handler 注册完成后发出）
    _controlChannel.invokeMethod('onReady');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.canvas,
      color: const Color(0xFF121414),
      child: Stack(
        children: [
          Positioned.fill(
            child: TerminalView(
              terminal,
              controller: controller,
              autofocus: true,
              textStyle: const TerminalStyle(fontSize: 14),
              padding: const EdgeInsets.all(4),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Text(
              'evt: $_lastEvent',
              style: const TextStyle(color: Color(0xFF7C8A99), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
