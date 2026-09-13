import 'dart:convert';
import 'dart:typed_data';

/// Incremental UTF-8 decoder for PTY output streams.
///
/// Chunks from the PTY can split a multi-byte character across writes; decoding
/// each chunk in isolation would emit U+FFFD. This decoder keeps the trailing
/// incomplete bytes buffered until their continuation bytes arrive.
///
/// It also normalizes bare `\n` to `\r\n` (MAUI parity: without it, LF-only
/// output renders as a staircase). A `\r` at the end of one chunk followed by
/// `\n` at the start of the next must not become `\r\r\n`.
class Utf8StreamDecoder {
  final List<int> _pending = [];
  bool _lastWasCr = false;

  /// Feed raw bytes, get display text ready for [Terminal.write].
  String feed(List<int> bytes) {
    if (bytes.isEmpty) return '';
    _pending.addAll(bytes);

    final keep = _incompleteTailLength();
    final decodable = _pending.length - keep;
    if (decodable <= 0) return '';

    final text = utf8.decode(bytesRange(_pending, 0, decodable));
    _pending.removeRange(0, decodable);
    return _normalizeNewlines(text);
  }

  /// Flush any buffered bytes at end of stream (malformed tail -> U+FFFD).
  String flush() {
    if (_pending.isEmpty) return '';
    final text = utf8.decode(_pending, allowMalformed: true);
    _pending.clear();
    return _normalizeNewlines(text);
  }

  /// Byte count of a trailing incomplete UTF-8 sequence (0 if none).
  int _incompleteTailLength() {
    var i = _pending.length - 1;
    // Walk back over continuation bytes (10xxxxxx), max 3 for a 4-byte seq.
    var continuation = 0;
    while (i >= 0 && (_pending[i] & 0xC0) == 0x80 && continuation < 3) {
      continuation++;
      i--;
    }
    if (i < 0) {
      // All continuation bytes — still incomplete, keep everything.
      return _pending.length;
    }
    final lead = _pending[i];
    final seqLen = _sequenceLength(lead);
    if (seqLen == 1) {
      // ASCII lead or invalid byte: nothing trailing is incomplete.
      return 0;
    }
    final actual = continuation + 1;
    return actual < seqLen ? actual : 0;
  }

  /// Expected sequence length from a lead byte; 1 for ASCII/invalid.
  static int _sequenceLength(int lead) {
    if ((lead & 0x80) == 0x00) return 1;
    if ((lead & 0xE0) == 0xC0) return 2;
    if ((lead & 0xF0) == 0xE0) return 3;
    if ((lead & 0xF8) == 0xF0) return 4;
    return 1;
  }

  String _normalizeNewlines(String text) {
    if (!text.contains('\n')) {
      _lastWasCr = text.endsWith('\r');
      return text;
    }
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '\n' && !_lastWasCr) {
        buf.write('\r\n');
      } else {
        buf.write(ch);
      }
      _lastWasCr = ch == '\r';
    }
    return buf.toString();
  }
}

/// Copy a range of a List<int> into a Uint8List for utf8.decode.
Uint8List bytesRange(List<int> source, int start, int end) {
  final out = Uint8List(end - start);
  for (var i = 0; i < out.length; i++) {
    out[i] = source[start + i] & 0xFF;
  }
  return out;
}
