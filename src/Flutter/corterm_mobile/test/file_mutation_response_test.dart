import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/core/api/api_client.dart';
import 'package:corterm_mobile/features/files/data/file_repository.dart';

import 'fakes.dart';

void main() {
  test('all file mutations accept empty successful HTTP responses', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final paths = <String>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          paths.add(request.path);
          handler.resolve(
            Response(requestOptions: request, statusCode: 200, data: ''),
          );
        },
      ),
    );
    final repo = FileRepository(
      ApiClient(
        baseUrl: 'https://example.test',
        tokenStore: FakeTokenStore(),
        dio: dio,
      ),
      Dio(),
      TransferRoutes(),
    );
    await repo.mkdir(workspaceId: 'ws', path: 'folder');
    await repo.writeText(workspaceId: 'ws', path: 'a', content: 'hello');
    await repo.rename(workspaceId: 'ws', path: 'a', newName: 'b');
    await repo.delete(workspaceId: 'ws', path: 'b');
    await repo.trash(workspaceId: 'ws', path: 'c', trashId: 'receipt');
    await repo.restoreTrash(workspaceId: 'ws', trashId: 'receipt');
    expect(paths.length, 6);
  });
}
