import 'package:flutter/material.dart';

import 'src/terminal_channels.dart';
import 'src/terminal_registry.dart';
import 'src/terminal_screen.dart';

/// CortexTerminal terminal renderer.
///
/// Hosted inside the ArkTS app via FlutterEntry/FlutterPage with a cached
/// engine: main() runs at app prewarm (EntryAbility, ~1.5s after launch), the
/// view is attached later when a terminal page opens. All host communication
/// goes through [TerminalChannels].
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final registry = TerminalRegistry(onOutput: (data) {
    TerminalChannels.instance.sendUserInput(data);
  });
  TerminalChannels.register(registry);
  runApp(TerminalHostApp(registry: registry));
}

class TerminalHostApp extends StatelessWidget {
  const TerminalHostApp({super.key, required this.registry});

  final TerminalRegistry registry;

  @override
  Widget build(BuildContext context) {
    // Single screen, always dark, no Navigator — the ArkTS host owns routing.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TerminalScreen(registry: registry),
    );
  }
}
