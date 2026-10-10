import 'package:flutter_test/flutter_test.dart';

import 'package:corterm_mobile/core/api/api_exception.dart';
import 'package:corterm_mobile/features/files/presentation/files_screen.dart';

void main() {
  group('filesParentPath（任务 B：系统返回逐级向上）', () {
    test('根路径的上一级仍是根', () {
      expect(filesParentPath(''), '');
    });
    test('单级目录回到根', () {
      expect(filesParentPath('docs'), '');
    });
    test('多级目录逐级上退', () {
      expect(filesParentPath('docs/sub'), 'docs');
      expect(filesParentPath('a/b/c'), 'a/b');
    });
  });

  group('isStalePathError（任务 A：恢复路径失效判定）', () {
    test('path_not_found / path_invalid 判定为失效', () {
      expect(isStalePathError(ApiException(404, serverMessage: 'path_not_found')),
          isTrue);
      expect(isStalePathError(ApiException(400, serverMessage: 'path_invalid')),
          isTrue);
    });
    test('其他错误码 / 非 ApiException 不算失效，照常上抛', () {
      expect(isStalePathError(ApiException(500, serverMessage: 'internal')), isFalse);
      expect(isStalePathError(ApiException(404, serverMessage: 'not_found')), isFalse);
      expect(isStalePathError(StateError('boom')), isFalse);
    });
  });
}
