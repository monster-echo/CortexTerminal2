import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/core/api/api_client.dart';
import 'package:corterm_mobile/features/files/data/file_repository.dart';
import 'package:corterm_mobile/features/files/data/file_transfer_control.dart';

import 'fakes.dart';

class _GrantApi extends ApiClient {
  _GrantApi()
    : super(baseUrl: 'https://example.test', tokenStore: FakeTokenStore());
  @override
  Future<Map<String, dynamic>> postMap(
    String path,
    Object? body, {
    CancelToken? cancelToken,
  }) async => {
    'endpoints': [
      {'url': 'https://lan.test/file', 'kind': 'lan'},
      {'url': 'https://relay.test/file', 'kind': 'relay'},
    ],
  };
}

void main() {
  for (final upload in [false, true]) {
    test(
      'cancelled ${upload ? 'upload' : 'download'} does not try another endpoint',
      () async {
        final control = FileTransferControl();
        final routes = TransferRoutes();
        final dio = Dio();
        var attempts = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              attempts++;
              control.cancel();
              handler.reject(control.cancelToken.cancelError!);
            },
          ),
        );
        final repo = FileRepository(_GrantApi(), dio, routes);
        final Future<Object?> operation = upload
            ? repo.upload(
                workspaceId: 'ws1',
                dirPath: '',
                filename: 'sample',
                bytes: Uint8List.fromList([1, 2]),
                control: control,
              )
            : repo.downloadBytes(
                workspaceId: 'ws1',
                path: 'sample',
                control: control,
              );
        await expectLater(
          operation,
          throwsA(
            isA<DioException>().having(
              (error) => error.type,
              'type',
              DioExceptionType.cancel,
            ),
          ),
        );
        expect(attempts, 1);
        expect(routes.value, isEmpty);
        control.dispose();
        routes.dispose();
        dio.close();
      },
    );
  }
  test(
    'failed LAN then Relay announces switch and records actual completed route',
    () async {
      final control = FileTransferControl();
      final routes = TransferRoutes();
      final dio = Dio();
      var announcedSwitch = false;
      control.addListener(() {
        if (control.route == 'relay' && control.switching) {
          announcedSwitch = true;
        }
      });
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.host == 'lan.test') {
              handler.reject(
                DioException.connectionError(
                  requestOptions: options,
                  reason: 'unreachable',
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: [1, 2, 3],
                ),
              );
            }
          },
        ),
      );
      final result = await FileRepository(
        _GrantApi(),
        dio,
        routes,
      ).downloadBytes(workspaceId: 'ws1', path: 'sample', control: control);
      expect(result, [1, 2, 3]);
      expect(announcedSwitch, isTrue);
      expect(routes.value.single.route, 'relay');
      control.dispose();
      routes.dispose();
      dio.close();
    },
  );
}
