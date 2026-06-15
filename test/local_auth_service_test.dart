import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final auth = LocalAuthService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await auth.clearProfile();
  });

  test('creates a local teacher profile and verifies the PIN', () async {
    await auth.createProfile(
      name: 'Ava Teacher',
      school: 'COC',
      pin: '1234',
    );

    expect(await auth.hasProfile(), isTrue);

    final profile = await auth.loadProfile();
    expect(profile?.name, 'Ava Teacher');
    expect(profile?.school, 'COC');

    await auth.lock();
    expect(auth.isUnlocked, isFalse);

    final result = await auth.verifyPin('1234');
    expect(result.success, isTrue);
    expect(auth.isUnlocked, isTrue);
  });

  test('lock keeps the offline PIN profile for the next unlock', () async {
    await auth.createProfile(
      name: 'Ava Teacher',
      school: 'COC',
      pin: '1234',
      cloudUserId: 'teacher-123',
    );

    await auth.lock();

    expect(await auth.hasProfile(), isTrue);
    expect(auth.isUnlocked, isFalse);

    final profile = await auth.loadProfile();
    expect(profile?.cloudUserId, 'teacher-123');

    final result = await auth.verifyPin('1234');
    expect(result.success, isTrue);
    expect(auth.isUnlocked, isTrue);
  });

  test('rejects invalid PINs and enters cooldown after repeated failures',
      () async {
    await auth.createProfile(
      name: 'Ava Teacher',
      school: 'COC',
      pin: '1234',
    );
    await auth.lock();

    for (var attempt = 0; attempt < 4; attempt++) {
      final result = await auth.verifyPin('9999');
      expect(result.success, isFalse);
      expect(result.cooldownRemaining, isNull);
    }

    final cooldownResult = await auth.verifyPin('9999');
    expect(cooldownResult.success, isFalse);
    expect(cooldownResult.cooldownRemaining, isNotNull);

    final blockedResult = await auth.verifyPin('1234');
    expect(blockedResult.success, isFalse);
    expect(blockedResult.cooldownRemaining, isNotNull);
  });
}
