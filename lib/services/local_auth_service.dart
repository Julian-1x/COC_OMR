import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalTeacherProfile {
  const LocalTeacherProfile({
    required this.name,
    required this.school,
    required this.createdAt,
    this.email,
    this.cloudUserId,
    this.lastUnlockedAt,
  });

  final String name;
  final String school;
  final DateTime createdAt;
  final String? email;
  final String? cloudUserId;
  final DateTime? lastUnlockedAt;
}

class LocalAuthResult {
  const LocalAuthResult._({
    required this.success,
    this.message,
    this.cooldownRemaining,
  });

  const LocalAuthResult.success() : this._(success: true);

  const LocalAuthResult.failure(String message)
      : this._(success: false, message: message);

  const LocalAuthResult.cooldown(Duration remaining)
      : this._(
          success: false,
          message: 'Too many attempts. Try again soon.',
          cooldownRemaining: remaining,
        );

  final bool success;
  final String? message;
  final Duration? cooldownRemaining;
}

class LocalAuthService {
  LocalAuthService._();

  static final LocalAuthService instance = LocalAuthService._();

  static const String _nameKey = 'local_auth_teacher_name';
  static const String _schoolKey = 'local_auth_school';
  static const String _emailKey = 'local_auth_email';
  static const String _cloudUserIdKey = 'local_auth_cloud_user_id';
  static const String _pinHashKey = 'local_auth_pin_hash';
  static const String _pinSaltKey = 'local_auth_pin_salt';
  static const String _createdAtKey = 'local_auth_created_at';
  static const String _lastUnlockedAtKey = 'local_auth_last_unlocked_at';
  static const String _failedAttemptsKey = 'local_auth_failed_attempts';
  static const String _cumulativeFailedAttemptsKey =
      'local_auth_cumulative_failed_attempts';
  static const String _cooldownUntilKey = 'local_auth_cooldown_until';

  static const int _maxFailedAttempts = 5;
  static const Duration _cooldownDuration = Duration(minutes: 1);

  bool _isUnlocked = false;
  String? _activeCloudUserId;

  bool get isUnlocked => _isUnlocked;
  String? get activeCloudUserId => _activeCloudUserId;

  Future<bool> hasProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_pinHashKey) &&
        prefs.containsKey(_pinSaltKey) &&
        prefs.containsKey(_nameKey);
  }

  Future<LocalTeacherProfile?> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_nameKey);
    final school = prefs.getString(_schoolKey);
    final email = prefs.getString(_emailKey);
    final cloudUserId = prefs.getString(_cloudUserIdKey);
    final createdAt = DateTime.tryParse(prefs.getString(_createdAtKey) ?? '');
    final lastUnlockedAt =
        DateTime.tryParse(prefs.getString(_lastUnlockedAtKey) ?? '');

    if (name == null || createdAt == null) {
      return null;
    }

    return LocalTeacherProfile(
      name: name,
      school: school ?? '',
      email: email,
      cloudUserId: cloudUserId,
      createdAt: createdAt,
      lastUnlockedAt: lastUnlockedAt,
    );
  }

  Future<void> createProfile({
    required String name,
    required String school,
    required String pin,
    String? email,
    String? cloudUserId,
  }) async {
    _validatePin(pin);
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Teacher name is required.');
    }

    final prefs = await SharedPreferences.getInstance();
    final salt = _createSalt();
    final now = DateTime.now().toIso8601String();

    await prefs.setString(_nameKey, trimmedName);
    await prefs.setString(_schoolKey, school.trim());
    await _setOrRemove(prefs, _emailKey, email?.trim().toLowerCase());
    await _setOrRemove(prefs, _cloudUserIdKey, cloudUserId?.trim());
    await prefs.setString(_pinSaltKey, salt);
    await prefs.setString(_pinHashKey, _hashPin(pin, salt));
    await prefs.setString(_createdAtKey, now);
    await prefs.setString(_lastUnlockedAtKey, now);
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_cumulativeFailedAttemptsKey);
    await prefs.remove(_cooldownUntilKey);
    _activeCloudUserId = cloudUserId?.trim();
    _isUnlocked = true;
  }

  Future<LocalAuthResult> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final cooldown = _cooldownRemaining(prefs);
    if (cooldown > Duration.zero) {
      return LocalAuthResult.cooldown(cooldown);
    }

    final storedHash = prefs.getString(_pinHashKey);
    final salt = prefs.getString(_pinSaltKey);
    if (storedHash == null || salt == null) {
      return const LocalAuthResult.failure('No local profile is set up yet.');
    }

    if (_hashPin(pin, salt) == storedHash) {
      _isUnlocked = true;
      await prefs.remove(_failedAttemptsKey);
      await prefs.remove(_cumulativeFailedAttemptsKey);
      await prefs.remove(_cooldownUntilKey);
      await prefs.setString(
        _lastUnlockedAtKey,
        DateTime.now().toIso8601String(),
      );
      _activeCloudUserId = prefs.getString(_cloudUserIdKey);
      return const LocalAuthResult.success();
    }

    final attempts = (prefs.getInt(_failedAttemptsKey) ?? 0) + 1;
    final cumulative =
        (prefs.getInt(_cumulativeFailedAttemptsKey) ?? 0) + 1;
    await prefs.setInt(_failedAttemptsKey, attempts);
    await prefs.setInt(_cumulativeFailedAttemptsKey, cumulative);
    if (attempts >= _maxFailedAttempts) {
      final rounds = cumulative ~/ _maxFailedAttempts;
      final cooldownMinutes = switch (rounds) {
        <= 1 => 1,
        2 => 5,
        3 => 15,
        _ => 30,
      };
      final cooldownUntil =
          DateTime.now().add(Duration(minutes: cooldownMinutes));
      await prefs.setString(_cooldownUntilKey, cooldownUntil.toIso8601String());
      await prefs.setInt(_failedAttemptsKey, 0);
      return LocalAuthResult.cooldown(Duration(minutes: cooldownMinutes));
    }

    final remaining = _maxFailedAttempts - attempts;
    return LocalAuthResult.failure(
      'Incorrect PIN. $remaining attempt${remaining == 1 ? '' : 's'} left.',
    );
  }

  Future<void> trustCloudAccount({
    required String name,
    required String school,
    required String email,
    required String cloudUserId,
    required String pin,
  }) {
    return createProfile(
      name: name,
      school: school,
      email: email,
      cloudUserId: cloudUserId,
      pin: pin,
    );
  }

  Future<void> lock() async {
    _isUnlocked = false;
    _activeCloudUserId = null;
  }

  Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey);
    await prefs.remove(_schoolKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_cloudUserIdKey);
    await prefs.remove(_pinHashKey);
    await prefs.remove(_pinSaltKey);
    await prefs.remove(_createdAtKey);
    await prefs.remove(_lastUnlockedAtKey);
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_cumulativeFailedAttemptsKey);
    await prefs.remove(_cooldownUntilKey);
    _isUnlocked = false;
    _activeCloudUserId = null;
  }

  Duration _cooldownRemaining(SharedPreferences prefs) {
    final until = DateTime.tryParse(prefs.getString(_cooldownUntilKey) ?? '');
    if (until == null) {
      return Duration.zero;
    }
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _createSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  Future<void> _setOrRemove(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, value);
  }

  void _validatePin(String pin) {
    final valid = RegExp(r'^\d{4,6}$').hasMatch(pin);
    if (!valid) {
      throw ArgumentError('PIN must be 4 to 6 digits.');
    }
  }
}
