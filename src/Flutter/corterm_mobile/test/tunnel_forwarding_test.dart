import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:corterm_mobile/core/api/api_client.dart';
import 'package:corterm_mobile/core/auth/token_store.dart';
import 'package:corterm_mobile/features/tunnels/data/tunnel_repository.dart';
import 'package:corterm_mobile/features/tunnels/presentation/port_forwarding_screen.dart';

import 'pages/test_harness.dart';

class _TunnelApi extends ApiClient {
  _TunnelApi(TokenStore tokens)
    : super(baseUrl: 'https://example.test', tokenStore: tokens);
  final entry = <String, dynamic>{
    'tunnelId': 't1',
    'localPort': 3000,
    'remotePort': 3000,
    'remoteAddress': '127.0.0.1',
    'url': 'https://example.test/relay/t/test/',
    'expiresAtUtc': '2030-01-01T00:00:00Z',
  };
  @override
  Future<Map<String, dynamic>> postMap(
    String path,
    Object? body, {
    CancelToken? cancelToken,
  }) async => {...entry, 'url': '${entry['url']}?k=test-secret'};
  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async => {
    'tunnels': [entry],
  };
  @override
  Future<void> delete(String path) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await initPageTestFixtures();
  });
  testWidgets('new rule has a ready default and hides advanced fields', (
    tester,
  ) async {
    await settlePage(tester, const PortForwardingScreen(workspaceId: 'ws1'));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '3000',
    );
    expect(find.text('名称（自动生成）'), findsNothing);
    final create = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '创建并启动'),
    );
    expect(create.onPressed, isNotNull);
  });
  testWidgets('target changes keep the default entry port in sync', (
    tester,
  ) async {
    await settlePage(tester, const PortForwardingScreen(workspaceId: 'ws1'));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '8080');
    await tester.pump();
    await tester.tap(find.text('高级设置（可选）'));
    await tester.pumpAndSettle();
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(
      fields.map((f) => f.controller!.text),
      containsAll(['8080', '127.0.0.1']),
    );
    expect(fields.where((f) => f.controller!.text == '8080').length, 2);
  });
  testWidgets('invalid ports cannot be submitted', (tester) async {
    await settlePage(tester, const PortForwardingScreen(workspaceId: 'ws1'));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    for (final value in ['0', '65536', '']) {
      await tester.enterText(find.byType(TextField), value);
      await tester.pump();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, '创建并启动'),
            )
            .onPressed,
        isNull,
      );
    }
  });

  test(
    'access key survives a new repository and is removed on revoke',
    () async {
      const secure = FlutterSecureStorage();
      final tokens = TokenStore(secure);
      await tokens.save(token: 'test', username: 'alice');
      final api = _TunnelApi(tokens);
      final repo = TunnelRepository(api, storage: secure);
      final created = await repo.create(
        workspaceId: 'w',
        localPort: 3000,
        remotePort: 3000,
      );
      expect(created.hasAccessKey, isTrue);
      final reloaded = TunnelRepository(api, storage: secure);
      expect((await reloaded.list('w')).single.hasAccessKey, isTrue);
      await reloaded.revoke('t1');
      expect((await reloaded.list('w')).single.hasAccessKey, isFalse);
    },
  );
  test('access keys are scoped to the signed in account', () async {
    const secure = FlutterSecureStorage();
    final tokens = TokenStore(secure);
    await tokens.save(token: 'test', username: 'alice');
    final api = _TunnelApi(tokens);
    final repo = TunnelRepository(api, storage: secure);
    await repo.create(workspaceId: 'w', localPort: 3000, remotePort: 3000);
    await tokens.save(token: 'test2', username: 'bob');
    expect((await repo.list('w')).single.hasAccessKey, isFalse);
  });
}
