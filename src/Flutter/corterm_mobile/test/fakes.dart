
import 'package:corterm_mobile/core/auth/token_store.dart';
import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:corterm_mobile/core/ws/terminal_socket.dart';
import 'package:corterm_mobile/core/ws/ws_frames.dart';
import 'package:corterm_mobile/features/files/data/file_repository.dart';
import 'package:corterm_mobile/features/session/session_controller.dart';
import 'package:corterm_mobile/features/sessions/data/session_repository.dart';
import 'package:corterm_mobile/features/tunnels/data/tunnel_repository.dart';

/// 测试共享假实现：不建真连、不访问网络。

class FakeTokenStore implements TokenStore {
  @override
  String? get token => 'fake-token';
  @override
  String? get username => 'tester';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSocket implements TerminalSocket {
  @override
  Stream<ServerFrame> get frames => const Stream.empty();

  @override
  bool get closedByUs => false;

  @override
  bool get detachedByUs => false;

  @override
  bool get sessionNotFound => false;

  @override
  void forceClose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeSessionRepo implements SessionRepository {
  @override
  Future<void> rememberCurrent(String? sessionId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// 测试不建真连：socket 工厂返回空帧流假 socket。
class FakeSessionController extends SessionController {
  FakeSessionController(AppPreferences prefs)
      : super(
          _FakeSessionRepo(),
          ({required String sessionId, int sinceSeq = 0}) async =>
              _FakeSocket(),
          prefs,
        );

  void seed(SessionState state) => this.state = state;
}

class FakeFileRepo implements FileRepository {
  @override
  Future<FileListing> list(
      {required String workspaceId, required String path}) async {
    return const FileListing(entries: [
      FileEntry(
          name: 'lib',
          isDirectory: true,
          sizeBytes: 0,
          modifiedUtc: null),
      FileEntry(
          name: 'README.md',
          isDirectory: false,
          sizeBytes: 1234,
          modifiedUtc: null),
      FileEntry(
          name: 'pubspec.yaml',
          isDirectory: false,
          sizeBytes: 567,
          modifiedUtc: null),
    ], truncated: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeTunnelRepo implements TunnelRepository {
  @override
  Future<List<TunnelSummary>> list(String sessionId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
