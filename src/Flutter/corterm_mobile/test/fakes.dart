
import 'package:corterm_mobile/core/auth/token_store.dart';
import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:corterm_mobile/core/ws/terminal_socket.dart';
import 'package:corterm_mobile/core/ws/ws_frames.dart';
import 'package:corterm_mobile/features/files/data/file_repository.dart';
import 'package:corterm_mobile/features/session/session_controller.dart';
import 'dart:typed_data';

import 'package:corterm_mobile/features/membership/data/membership_repository.dart';
import 'package:corterm_mobile/features/profile/data/profile_repository.dart';
import 'package:corterm_mobile/features/sessions/data/session_repository.dart';
import 'package:corterm_mobile/features/support/data/support_repository.dart';
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

class FakeProfileRepo implements ProfileRepository {
  @override
  Future<UserProfile> get() async => UserProfile(
        id: 'u1',
        username: 'tester',
        email: 'tester@example.com',
        displayName: 'tester',
        hasPassword: true,
      );

  @override
  String resolveAvatarUrl(String? avatarUrl) => avatarUrl ?? '';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeSupportRepo implements SupportRepository {
  @override
  Future<SupportInfo> get() async => SupportInfo(
        email: 'support@example.com',
        qqGroup: SupportGroup(name: 'QQ', number: '123', qrCodeUrl: ''),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeMembershipRepo implements MembershipRepository {
  @override
  Future<ReferralSummary> referral() async => ReferralSummary(
        code: 'INVITE-1',
        rewardDaysPerInvite: 7,
        invitedCount: 0,
        totalRewardDays: 0,
        rewards: const [],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// 一次 listForWorker 调用记录（用于断言浏览导航）。
class FileListingCall {
  FileListingCall(this.root, this.path);
  final String root;
  final String path;
}

class FakeFileRepo implements FileRepository {
  /// 记录 listForWorker 的调用（导航断言用）。
  final List<FileListingCall> listForWorkerCalls = [];

  /// 可注入的目录内容；缺省返回固定列表。
  Object Function(String root, String path)? listingBuilder; // FileListing 或 Future<FileListing>

  @override
  Future<FileListing> listForWorker(
      {required String workerId, String root = '', String path = ''}) async {
    listForWorkerCalls.add(FileListingCall(root, path));
    if (listingBuilder != null) {
      final out = listingBuilder!(root, path);
      if (out is FileListing) return out;
      if (out is Future<FileListing>) return out;
    }
    return const FileListing(entries: [
      FileEntry(
          name: 'Projects',
          isDirectory: true,
          sizeBytes: 0,
          modifiedUtc: null),
    ], truncated: false);
  }

  @override
  Future<Uint8List> downloadBytes(
      {required String workspaceId, required String path}) async {
    return Uint8List.fromList('hello corterm'.codeUnits);
  }

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
