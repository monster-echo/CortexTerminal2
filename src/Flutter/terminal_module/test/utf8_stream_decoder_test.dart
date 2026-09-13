import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_module/src/utf8_stream_decoder.dart';

void main() {
  group('Utf8StreamDecoder', () {
    test('ascii passthrough', () {
      final d = Utf8StreamDecoder();
      expect(d.feed(utf8.encode('hello world')), 'hello world');
    });

    test('multi-byte char in one chunk', () {
      final d = Utf8StreamDecoder();
      expect(d.feed(utf8.encode('中文')), '中文');
    });

    test('4-byte emoji split across chunks', () {
      final d = Utf8StreamDecoder();
      final bytes = utf8.encode('x\u{1F600}y'); // x 😀 y
      final cut = bytes.indexOf(0xF0); // emoji lead byte
      final a = d.feed(bytes.sublist(0, cut));
      final b = d.feed(bytes.sublist(cut));
      expect('$a$b', 'x\u{1F600}y');
      expect(a, isNot(contains('\u{FFFD}')));
    });

    test('3-byte CJK split after lead byte', () {
      final d = Utf8StreamDecoder();
      final bytes = utf8.encode('中'); // E4 B8 AD
      final a = d.feed([bytes[0]]);
      final b = d.feed(bytes.sublist(1));
      expect('$a$b', '中');
    });

    test('3-byte CJK split after lead + 1 continuation', () {
      final d = Utf8StreamDecoder();
      final bytes = utf8.encode('中'); // E4 B8 AD
      final a = d.feed(bytes.sublist(0, 2));
      final b = d.feed(bytes.sublist(2));
      expect('$a$b', '中');
    });

    test('2-byte char split', () {
      final d = Utf8StreamDecoder();
      final bytes = utf8.encode('é'); // C3 A9
      final a = d.feed([bytes[0]]);
      final b = d.feed(bytes.sublist(1));
      expect('$a$b', 'é');
    });

    test('LF normalized to CRLF', () {
      final d = Utf8StreamDecoder();
      expect(d.feed('a\nb'.codeUnits), 'a\r\nb');
    });

    test('CRLF not double-converted across chunk boundary', () {
      final d = Utf8StreamDecoder();
      final a = d.feed('a\r'.codeUnits);
      final b = d.feed('\nb'.codeUnits);
      expect('$a$b', 'a\r\nb');
    });

    test('mixed multi-byte and newline chunks', () {
      final d = Utf8StreamDecoder();
      final bytes = utf8.encode('行\n完');
      final cut = utf8.encode('行').length; // after first char
      var out = '';
      out += d.feed(bytes.sublist(0, cut));
      out += d.feed(bytes.sublist(cut, cut + 1)); // the \n
      out += d.feed(bytes.sublist(cut + 1));
      expect(out, '行\r\n完');
    });

    test('flush emits malformed tail as replacement chars', () {
      final d = Utf8StreamDecoder();
      d.feed([0xE4]); // lead only
      final text = d.flush();
      expect(text, '\u{FFFD}');
    });
  });
}
