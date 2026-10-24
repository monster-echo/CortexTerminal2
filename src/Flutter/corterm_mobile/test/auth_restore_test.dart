import 'dart:async';

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

class _HangingTokenStore implements TokenStore {
  final _loadCompleter = Completer<void>();

  @override
  String? get token => null;

  @override
  String? get username => null;

  @override
  Future<void> load() => _loadCompleter.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Keychain restore failure falls back to signed-out state', () async {
    final controller = AuthController(_FailingTokenStore());

    await expectLater(controller.restore(), completes);

    expect(controller.state.status, AuthStatus.unauthenticated);
  });

  test(
    'hung Keychain restore times out and falls back to signed-out state',
    () async {
      final controller = AuthController(
        _HangingTokenStore(),
        restoreTimeout: const Duration(milliseconds: 10),
      );

      await expectLater(controller.restore(), completes);

      expect(controller.state.status, AuthStatus.unauthenticated);
    },
  );

  test('repeated Keychain failures never leave auth in loading state', () async {
    final controller = AuthController(_FailingTokenStore());

    // Exercise the startup recovery path repeatedly to catch notifier state or
    // asynchronous error handling that only fails after multiple attempts.
    for (var attempt = 0; attempt < 500; attempt++) {
      await controller.restore();
      expect(controller.state.status, AuthStatus.unauthenticated);
    }
  });

  test(
    'concurrent hung restores all recover within the configured timeout',
    () async {
      final controllers = List.generate(
        100,
        (_) => AuthController(
          _HangingTokenStore(),
          restoreTimeout: const Duration(milliseconds: 10),
        ),
      );

      await Future.wait(controllers.map((controller) => controller.restore()));

      expect(
        controllers.map((controller) => controller.state.status),
        everyElement(AuthStatus.unauthenticated),
      );
      for (final controller in controllers) {
        controller.dispose();
      }
    },
  );
}
