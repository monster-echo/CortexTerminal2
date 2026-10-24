import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS Keychain can read, write, and delete auth values', (
    tester,
  ) async {
    const storage = FlutterSecureStorage();
    const key = 'corterm.ios.keychain.smoke';
    const value = 'simulator-smoke-value';

    await storage.delete(key: key);
    await storage.write(key: key, value: value);
    expect(await storage.read(key: key), value);
    await storage.delete(key: key);
    expect(await storage.read(key: key), isNull);
  });

  testWidgets('iOS Keychain survives repeated auth-value operations', (
    tester,
  ) async {
    const storage = FlutterSecureStorage();
    const key = 'corterm.ios.keychain.stress';

    for (var iteration = 0; iteration < 25; iteration++) {
      final value = 'stress-value-$iteration';
      await storage.write(key: key, value: value);
      expect(
        await storage.read(key: key),
        value,
        reason: 'iteration $iteration',
      );
      await storage.delete(key: key);
      expect(
        await storage.read(key: key),
        isNull,
        reason: 'iteration $iteration',
      );
    }
  });
}
