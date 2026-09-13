import 'dart:async';
import 'dart:convert' show jsonEncode, utf8;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show FocusManager;

import 'terminal_registry.dart';

/// Bridge between the ArkTS host and the Dart terminal stack.
///
/// Channels (see docs in the repo plan):
///   MethodChannel  'cortexterminal/terminal_control'
///     ArkTS -> Dart: attach{sessionId} -> bool hasContent
///                    reset{sessionId}, detach, unfocus,
///                    getSize{sessionId} -> {cols, rows}
///     Dart  -> ArkTS: onReady, onResize{cols, rows} (150ms debounce),
///                     onError{code, message}
///   BasicMessageChannel 'cortexterminal/pty_output'  ArkTS -> Dart (bytes)
///   BasicMessageChannel 'cortexterminal/user_input'  Dart  -> ArkTS (bytes)
class TerminalChannels {
  TerminalChannels._(this._registry) {
    _registry.addListener(_onRegistryChanged);
    _resizeSub = _registry.resizeStream.listen(_onResizeEvent);
  }

  static TerminalChannels? _instance;

  /// Wire the channels to the engine messenger. Called once from main() —
  /// with the cached engine this runs at app prewarm, long before the first
  /// terminal page exists.
  static TerminalChannels register(TerminalRegistry registry) {
    if (_instance != null) {
      return _instance!;
    }
    final channels = TerminalChannels._(registry);
    _instance = channels;
    channels._bind();
    return channels;
  }

  static TerminalChannels get instance => _instance!;

  final TerminalRegistry _registry;
  final _control = const MethodChannel('cortexterminal/terminal_control');
  final _ptyOutput = const BasicMessageChannel<ByteData>(
    'cortexterminal/pty_output',
    BinaryCodec(),
  );
  final _userInput = const BasicMessageChannel<ByteData>(
    'cortexterminal/user_input',
    BinaryCodec(),
  );

  StreamSubscription<ResizeEvent>? _resizeSub;
  Timer? _resizeDebounce;
  ResizeEvent? _pendingResize;

  void _bind() {
    _control.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'attach':
          final args = call.arguments as Map<Object?, Object?>?;
          final sessionId = (args?['sessionId'] as String?) ?? '';
          if (sessionId.isEmpty) {
            throw ArgumentError('attach requires sessionId');
          }
          _registry.attach(sessionId);
          return {'hasContent': _registry.hasContent(sessionId)};
        case 'reset':
          final args = call.arguments as Map<Object?, Object?>?;
          final sessionId = (args?['sessionId'] as String?) ?? '';
          _registry.reset(sessionId);
          return null;
        case 'detach':
          _registry.detach();
          return null;
        case 'unfocus':
          _unfocus();
          return null;
        case 'paste':
          final args = call.arguments as Map<Object?, Object?>?;
          final sessionId = (args?['sessionId'] as String?) ?? '';
          final text = (args?['text'] as String?) ?? '';
          if (text.isNotEmpty) {
            _registry.paste(sessionId, text);
          }
          return null;
        case 'getSize':
          final args = call.arguments as Map<Object?, Object?>?;
          final sessionId = (args?['sessionId'] as String?) ?? '';
          final terminal =
              _registry.terminalFor(sessionId) ?? _registry.activeTerminal;
          if (terminal == null) {
            return '{"cols":0,"rows":0}';
          }
          // JSON string: the ArkTS side JSON.parses it, matching the old
          // WebView build's getTerminalSize() contract.
          return jsonEncode({
            'cols': terminal.viewWidth,
            'rows': terminal.viewHeight,
          });
        default:
          throw MissingPluginException('unknown method ${call.method}');
      }
    });

    _ptyOutput.setMessageHandler((data) async {
      if (data != null && data.lengthInBytes > 0) {
        final sessionId = _registry.activeId;
        if (sessionId != null) {
          _registry.write(sessionId, data.buffer.asUint8List());
        }
      }
      return ByteData(0);
    });
  }

  void _onRegistryChanged() {
    // First attach happens after the ArkTS page is up and its handler bound —
    // the engine may have been prewarmed long before, so re-announce readiness
    // on every attach instead of once at startup.
    if (_registry.activeTerminal != null) {
      _control.invokeMethod('onReady').catchError((Object e) {
        // ArkTS side not bound yet — page attaches again on next entry.
      });
    }
  }

  void _onResizeEvent(ResizeEvent event) {
    if (event.sessionId != _registry.activeId) return;
    _pendingResize = event;
    _resizeDebounce?.cancel();
    // Parity with the WebView build: xterm.js debounced resize reports at
    // 150ms so keyboard-induced intermediate sizes don't SIGWINCH the server.
    _resizeDebounce = Timer(const Duration(milliseconds: 150), () {
      final e = _pendingResize;
      if (e == null) return;
      _pendingResize = null;
      _control
          .invokeMethod('onResize', {'cols': e.cols, 'rows': e.rows})
          .catchError((Object e) {});
    });
  }

  void sendUserInput(String data) {
    if (data.isEmpty) return;
    final bytes = utf8.encode(data);
    _userInput.send(ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length));
  }

  void _unfocus() {
    // Dismiss the soft keyboard, mirroring the WebView build's textarea blur.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void dispose() {
    _resizeSub?.cancel();
    _resizeDebounce?.cancel();
    _registry.removeListener(_onRegistryChanged);
  }
}
