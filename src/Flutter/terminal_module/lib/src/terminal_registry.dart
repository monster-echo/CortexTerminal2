import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import 'corterm_theme.dart';
import 'utf8_stream_decoder.dart';

/// Per-session terminal state. Terminals live in [TerminalRegistry], which
/// itself lives as long as the Flutter engine (cached engine) — so scrollback
/// survives page navigation on the ArkTS side.
class _Session {
  _Session(this._emitResize) : decoder = Utf8StreamDecoder() {
    terminal = Terminal(
      maxLines: terminalMaxLines,
      onOutput: (data) => onOutput?.call(data),
      onResize: (width, height, _, _) => _emitResize(sessionId, width, height),
    );
    controller = TerminalController();
  }

  late final Terminal terminal;
  late final TerminalController controller;
  final Utf8StreamDecoder decoder;
  final void Function(String sessionId, int cols, int rows) _emitResize;

  /// Set by the registry after construction.
  String sessionId = '';
  void Function(String data)? onOutput;

  /// True once any bytes were written — approximates "has scrollback/screen
  /// content" for the reattach-skip decision.
  bool hasWritten = false;
}

/// Owns one [Terminal] per session id, plus which session the view shows.
///
/// The ArkTS host drives it through the terminal_control channel:
///   attach {sessionId}  -> show (or lazily create) that session's terminal
///   reset  {sessionId}  -> wipe screen+scrollback (reattach replay path)
///   detach              -> keep buffers, view will go away
class TerminalRegistry extends ChangeNotifier {
  TerminalRegistry({void Function(String data)? onOutput}) : _onOutput = onOutput;

  final void Function(String data)? _onOutput;
  final Map<String, _Session> _sessions = {};
  String? _activeId;

  String? get activeId => _activeId;

  /// The terminal the view should render, or null before the first attach.
  Terminal? get activeTerminal => _sessions[_activeId]?.terminal;

  TerminalController? get activeController => _sessions[_activeId]?.controller;

  bool hasContent(String sessionId) => _sessions[sessionId]?.hasWritten ?? false;

  Terminal attach(String sessionId) {
    var session = _sessions[sessionId];
    if (session == null) {
      session = _createSession(sessionId);
    }
    _activeId = sessionId;
    notifyListeners();
    return session.terminal;
  }

  void detach() {
    // Keep buffers — reattach must restore, not replay.
    _activeId = null;
    notifyListeners();
  }

  /// Wipe the session (used before a full server replay; xterm 4.0 has no
  /// hard-reset API, so the Terminal object is replaced).
  Terminal reset(String sessionId) {
    final old = _sessions[sessionId];
    old?.controller.dispose();
    final session = _createSession(sessionId);
    if (_activeId == sessionId) {
      notifyListeners();
    }
    return session.terminal;
  }

  void write(String sessionId, List<int> bytes) {
    final session = _sessions[sessionId];
    if (session == null || bytes.isEmpty) return;
    session.hasWritten = true;
    session.terminal.write(session.decoder.feed(bytes));
  }

  void paste(String sessionId, String text) {
    _sessions[sessionId]?.terminal.paste(text);
  }

  _Session _createSession(String sessionId) {
    final session = _Session(_onResizeEvent)..sessionId = sessionId;
    session.onOutput = (data) => _onOutput?.call(data);
    _sessions[sessionId] = session;
    return session;
  }

  /// The terminal of a specific session, or null if not attached yet.
  Terminal? terminalFor(String sessionId) => _sessions[sessionId]?.terminal;

  final _resizeController = StreamController<ResizeEvent>.broadcast();

  void _onResizeEvent(String sessionId, int cols, int rows) {
    _resizeController.add(ResizeEvent(sessionId, cols, rows));
  }

  /// Raw resize events (autoResize layout changes). The channels layer
  /// debounces before reporting to ArkTS.
  Stream<ResizeEvent> get resizeStream => _resizeController.stream;

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.controller.dispose();
    }
    _sessions.clear();
    _resizeController.close();
    super.dispose();
  }
}

class ResizeEvent {
  ResizeEvent(this.sessionId, this.cols, this.rows);
  final String sessionId;
  final int cols;
  final int rows;
}
