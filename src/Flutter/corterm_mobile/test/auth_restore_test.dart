import 'package:corterm_mobile/core/auth/auth_controller.dart';
import 'package:corterm_mobile/core/auth/token_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingTokenStore implements TokenStore {
  @override
  String? get token => null;

  @override
  String? get username => null;

  @override
  Future<void> load() async {
    throw PlatformException(
      code: '-34018',
      message: 'A required entitlement is not present.',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Keychain restore failure falls back to signed-out state', () async {
    final controller = AuthController(_FailingTokenStore());

    await expectLater(controller.restore(), completes);

    expect(controller.state.status, AuthStatus.unauthenticated);
  });
}
