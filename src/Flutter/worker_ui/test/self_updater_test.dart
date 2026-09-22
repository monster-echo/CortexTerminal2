import 'package:flutter_test/flutter_test.dart';
import 'package:worker_ui/core/self_updater.dart';

void main() {
  group('Version.parse', () {
    test('解析点分数字版本', () {
      expect(Version.parse('0.1.0').parts, [0, 1, 0]);
      expect(Version.parse('1.22').parts, [1, 22]);
    });

    test('非数字段抛 FormatException', () {
      expect(() => Version.parse('0.1.0-beta'), throwsFormatException);
      expect(() => Version.parse('abc'), throwsFormatException);
      expect(() => Version.parse(''), throwsFormatException);
    });
  });

  group('versionCompare', () {
    test('正常比较', () {
      expect(versionCompare('0.2.0', '0.1.9'), greaterThan(0));
      expect(versionCompare('0.1.9', '0.2.0'), lessThan(0));
      expect(versionCompare('1.0.0', '1.0.0'), 0);
    });

    test('段数不齐时短的补 0', () {
      expect(versionCompare('1.0', '1.0.0'), 0);
      expect(versionCompare('1.0.1', '1.0'), greaterThan(0));
    });
  });
}
