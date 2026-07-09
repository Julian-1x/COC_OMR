import 'package:flutter/foundation.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:omr_app/services/local_data_store.dart';

class CloudTeacherAccount {
  const CloudTeacherAccount({
    required this.id,
    required this.email,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String email;
  final String name;
  final bool isActive;
}

class CloudAuthException implements Exception {
  const CloudAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TeacherRegistrationResult {
  const TeacherRegistrationResult({
    this.account,
    this.needsEmailConfirmation = false,
    this.pendingEmail,
    this.pendingName,
    this.pendingSchool,
  });

  final CloudTeacherAccount? account;
  final bool needsEmailConfirmation;
  final String? pendingEmail;
  final String? pendingName;
  final String? pendingSchool;
}

class CloudAuthService {
  CloudAuthService._();

  static final CloudAuthService instance = CloudAuthService._();

  Future<TeacherRegistrationResult> registerTeacher({
    required String name,
    required String email,
    required String password,
    required String school,
  }) async {
    _ensureApiReady();
    final trimmedName = name.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final trimmedSchool = school.trim();

    try {
      final response = await ApiService.postJson(
        '/register',
        <String, dynamic>{
          'email': normalizedEmail,
          'password': password,
          'password_confirmation': password,
          'full_name': trimmedName,
          'school': trimmedSchool,
        },
        auth: false,
      );

      final verified = _isEmailVerified(response);
      if (!verified) {
        await ApiService.clearSession();
        return TeacherRegistrationResult(
          needsEmailConfirmation: true,
          pendingEmail: normalizedEmail,
          pendingName: trimmedName,
          pendingSchool: trimmedSchool,
        );
      }

      final account = await _accountFromAuthResponse(response);
      if (account == null) {
        throw const CloudAuthException(
          'Registration could not start. Check your internet and try again.',
        );
      }

      return TeacherRegistrationResult(account: account);
    } catch (error) {
      if (error is CloudAuthException) {
        rethrow;
      }
      throw CloudAuthException(_friendlyError(error));
    }
  }

  /// Ask the server to email a password-reset link. Always resolves without
  /// revealing whether the email exists (the API responds generically).
  Future<void> requestPasswordReset({required String email}) async {
    _ensureApiReady();
    final normalizedEmail = email.trim().toLowerCase();
    try {
      await ApiService.postJson(
        '/forgot-password',
        <String, dynamic>{'email': normalizedEmail},
        auth: false,
      );
    } catch (error) {
      throw CloudAuthException(_friendlyError(error));
    }
  }

  /// Resend registration confirmation email (no login required).
  Future<void> resendEmailVerification({required String email}) async {
    _ensureApiReady();
    final normalizedEmail = email.trim().toLowerCase();
    try {
      await ApiService.postJson(
        '/email/resend-verification',
        <String, dynamic>{'email': normalizedEmail},
        auth: false,
      );
    } catch (error) {
      throw CloudAuthException(_friendlyError(error));
    }
  }

  Future<void> signOut() async {
    await LocalAuthService.instance.lock();
    if (ApiService.hasActiveSession) {
      try {
        await ApiService.postJson('/logout', const <String, dynamic>{});
      } catch (error) {
        debugPrint('Logout request failed: $error');
      }
    }
    await ApiService.clearSession();
    await LocalDataStore.instance.clearMemoryOnAuthReset();
  }

  Future<CloudTeacherAccount?> accountFromCurrentSession() async {
    if (!ApiService.hasActiveSession) {
      return null;
    }

    try {
      final response = await ApiService.getJson('/me');
      return _accountFromMeResponse(response);
    } catch (error) {
      debugPrint('Failed to resolve session account: $error');
      final userId = ApiService.currentUserId;
      final email = ApiService.currentEmail;
      if (userId == null) {
        return null;
      }
      return CloudTeacherAccount(
        id: userId,
        email: email ?? '',
        name: email ?? 'Teacher',
        isActive: true,
      );
    }
  }

  Future<CloudTeacherAccount> signInTeacher({
    required String email,
    required String password,
  }) async {
    _ensureApiReady();
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final response = await ApiService.postJson(
        '/login',
        <String, dynamic>{
          'email': normalizedEmail,
          'password': password,
          'device_name': 'mobile',
        },
        auth: false,
      );

      final account = await _accountFromAuthResponse(response);
      if (account == null) {
        throw const CloudAuthException('Sign in failed. Try again.');
      }

      if (!account.isActive) {
        await ApiService.clearSession();
        throw const CloudAuthException(
          'This teacher account is disabled. Ask the admin to reactivate it.',
        );
      }

      if (!_isEmailVerified(response)) {
        await ApiService.clearSession();
        throw const CloudAuthException(
          'This email has not been confirmed yet. Open the confirmation email, then sign in again.',
        );
      }

      return account;
    } catch (error) {
      throw CloudAuthException(_friendlyError(error));
    }
  }

  Future<void> applyTokenFromEmailVerification(String token) async {
    _ensureApiReady();
    await ApiService.setSession(
      token: token,
      userId: '',
      email: null,
    );

    final response = await ApiService.getJson('/me');
    final account = _accountFromMeResponse(response);
    if (account == null) {
      await ApiService.clearSession();
      throw const CloudAuthException(
        'Email was confirmed but sign-in failed. Try signing in with your password.',
      );
    }

    await ApiService.setSession(
      token: token,
      userId: account.id,
      email: account.email,
    );
  }

  void _ensureApiReady() {
    if (!ApiService.isReady) {
      throw const CloudAuthException(
        'School server is not connected. Reinstall the app with API_BASE_URL.',
      );
    }
  }

  Future<CloudTeacherAccount?> _accountFromAuthResponse(
    Map<String, dynamic> response,
  ) async {
    final token = response['token']?.toString();
    final user = response['user'];
    if (token == null || token.isEmpty || user is! Map) {
      return null;
    }

    final userMap = Map<String, dynamic>.from(user);
    final id = userMap['id']?.toString();
    final email = userMap['email']?.toString() ?? '';
    if (id == null || id.isEmpty) {
      return null;
    }

    final profile = userMap['profile'];
    final profileMap = profile is Map
        ? Map<String, dynamic>.from(profile)
        : const <String, dynamic>{};
    final name = (profileMap['full_name'] as String?)?.trim();
    final isActive = profileMap['is_active'] != false;

    await ApiService.setSession(token: token, userId: id, email: email);

    return CloudTeacherAccount(
      id: id,
      email: email,
      name: name == null || name.isEmpty ? email : name,
      isActive: isActive,
    );
  }

  CloudTeacherAccount? _accountFromMeResponse(Map<String, dynamic> response) {
    final user = response['user'] ?? response;
    if (user is! Map) {
      return null;
    }
    final userMap = Map<String, dynamic>.from(user);
    final id = userMap['id']?.toString();
    final email = userMap['email']?.toString() ?? ApiService.currentEmail ?? '';
    if (id == null || id.isEmpty) {
      return null;
    }

    final profile = userMap['profile'];
    final profileMap = profile is Map
        ? Map<String, dynamic>.from(profile)
        : const <String, dynamic>{};
    final name = (profileMap['full_name'] as String?)?.trim();

    return CloudTeacherAccount(
      id: id,
      email: email,
      name: name == null || name.isEmpty ? email : name,
      isActive: profileMap['is_active'] != false,
    );
  }

  bool _isEmailVerified(Map<String, dynamic> response) {
    final user = response['user'];
    if (user is! Map) {
      return true;
    }
    final verifiedAt = user['email_verified_at'];
    return verifiedAt != null && verifiedAt.toString().isNotEmpty;
  }

  String _friendlyError(Object error) {
    if (error is CloudAuthException) {
      return error.message;
    }
    if (error is ApiException) {
      return _friendlyApiMessage(error);
    }
    return error.toString();
  }

  String _friendlyApiMessage(ApiException error) {
    final normalized = error.message.toLowerCase();
    if (normalized.contains('credentials') ||
        normalized.contains('incorrect')) {
      return 'The email or password is incorrect. Check the account details or reset your password.';
    }
    if (normalized.contains('email not confirmed') ||
        normalized.contains('not verified')) {
      return 'This email has not been confirmed yet. Open the confirmation email, then sign in again.';
    }
    if (normalized.contains('already been taken') ||
        normalized.contains('already registered')) {
      return 'An account with this email already exists. Use Login instead.';
    }
    if (normalized.contains('password')) {
      return 'The password does not meet requirements. Use at least 8 characters.';
    }
    if (normalized.contains('rate limit') || normalized.contains('too many')) {
      return 'Too many attempts. Wait a minute, then try again.';
    }
    return error.message;
  }
}
