import 'package:flutter/foundation.dart';
import 'package:omr_app/constants/coc_school.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/utils/person_name.dart';

class CloudTeacherAccount {
  const CloudTeacherAccount({
    required this.id,
    required this.email,
    required this.name,
    required this.isActive,
    this.accessStatus = 'approved',
    this.school,
    this.department,
  });

  final String id;
  final String email;
  final String name;
  final bool isActive;
  final String accessStatus;
  final String? school;
  final String? department;

  bool get isApproved =>
      isActive && accessStatus.toLowerCase() == 'approved';
}

enum CloudSessionState {
  /// Server answered and the account is still usable.
  valid,

  /// Server answered and the account is revoked, deleted, or signed out.
  invalid,

  /// Server could not be reached — say nothing about the account.
  unreachable,
}

class CloudSessionCheck {
  const CloudSessionCheck(this.state, [this.account]);

  final CloudSessionState state;
  final CloudTeacherAccount? account;

  bool get isValid => state == CloudSessionState.valid;
  bool get isInvalid => state == CloudSessionState.invalid;
  bool get isUnreachable => state == CloudSessionState.unreachable;
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
    this.needsAdminApproval = false,
    this.pendingEmail,
    this.pendingName,
    this.pendingSchool,
    this.message,
  });

  final CloudTeacherAccount? account;
  final bool needsEmailConfirmation;
  final bool needsAdminApproval;
  final String? pendingEmail;
  final String? pendingName;
  final String? pendingSchool;
  final String? message;
}

class TeacherSignInResult {
  const TeacherSignInResult({
    this.account,
    this.needsMfa = false,
    this.needsMfaEnrollment = false,
    this.mfaTicket,
    this.message,
    this.captchaRequired = false,
    this.captchaSiteKey,
  });

  final CloudTeacherAccount? account;
  final bool needsMfa;
  final bool needsMfaEnrollment;
  final String? mfaTicket;
  final String? message;
  final bool captchaRequired;
  final String? captchaSiteKey;

  bool get isComplete => account != null;
}

class CloudAuthService {
  CloudAuthService._();

  static final CloudAuthService instance = CloudAuthService._();

  Future<TeacherRegistrationResult> registerTeacher({
    required String name,
    required String email,
    required String password,
    required String department,
    String school = CocSchool.name,
  }) async {
    _ensureApiReady();
    final trimmedName = PersonName.normalize(name);
    if (trimmedName.isEmpty) {
      throw const CloudAuthException(
        'Enter your full name (first name, then last name).',
      );
    }
    final normalizedEmail = email.trim().toLowerCase();
    final trimmedSchool =
        school.trim().isEmpty ? CocSchool.name : school.trim();
    final normalizedDepartment = department.trim().toUpperCase();
    if (!CocSchool.isValidDepartment(normalizedDepartment)) {
      throw const CloudAuthException(
        'Select your COC department (COE, SCCJ, CMA, CIT, CEA, or CAHS).',
      );
    }

    try {
      final response = await ApiService.postJson(
        '/register',
        <String, dynamic>{
          'email': normalizedEmail,
          'password': password,
          'password_confirmation': password,
          'full_name': trimmedName,
          'school': trimmedSchool,
          'department': normalizedDepartment,
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
          message: response['message']?.toString(),
        );
      }

      if (_isAccessPending(response)) {
        await ApiService.clearSession();
        return TeacherRegistrationResult(
          needsAdminApproval: true,
          pendingEmail: normalizedEmail,
          pendingName: trimmedName,
          pendingSchool: trimmedSchool,
          message: response['message']?.toString(),
        );
      }

      final account = await _accountFromAuthResponse(response);
      if (account == null) {
        throw const CloudAuthException(
          'Registration could not start. Check your internet and try again.',
        );
      }

      if (!account.isApproved) {
        await ApiService.clearSession();
        return TeacherRegistrationResult(
          needsAdminApproval: true,
          pendingEmail: normalizedEmail,
          pendingName: trimmedName,
          pendingSchool: trimmedSchool,
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

  /// Asks the server who this session belongs to.
  ///
  /// Only the server can say an account is revoked. When the server cannot be
  /// reached the result is [CloudSessionState.unreachable] so the teacher keeps
  /// working offline instead of being signed out on exam day.
  Future<CloudSessionCheck> checkCurrentSession({
    bool signOutOnInvalid = false,
  }) async {
    if (!ApiService.hasActiveSession) {
      return const CloudSessionCheck(CloudSessionState.invalid);
    }

    try {
      final response = await ApiService.getJson('/me');
      final account = _accountFromMeResponse(response);
      if (account == null) {
        await ApiService.clearSession();
        if (signOutOnInvalid) {
          await signOut();
        }
        return const CloudSessionCheck(CloudSessionState.invalid);
      }
      return CloudSessionCheck(CloudSessionState.valid, account);
    } catch (error) {
      debugPrint('Failed to resolve session account: $error');
      if (error is ApiException && error.sessionInvalidated) {
        if (signOutOnInvalid) {
          await signOut();
        }
        return const CloudSessionCheck(CloudSessionState.invalid);
      }
      return const CloudSessionCheck(CloudSessionState.unreachable);
    }
  }

  /// Account for the stored session, or a cached stand-in while offline.
  /// Returns null only when the server confirmed the session is no longer valid.
  Future<CloudTeacherAccount?> accountFromCurrentSession() async {
    final check = await checkCurrentSession();
    if (check.isUnreachable) {
      return cachedSessionAccount();
    }
    return check.account;
  }

  /// Account details already stored on this phone, for offline screens.
  CloudTeacherAccount? cachedSessionAccount() {
    final userId = ApiService.currentUserId;
    if (userId == null || userId.isEmpty) {
      return null;
    }
    final email =
        ApiService.currentEmail ?? LocalAuthService.instance.cachedTeacherEmail;
    return CloudTeacherAccount(
      id: userId,
      email: email ?? '',
      name: LocalAuthService.instance.cachedTeacherName ?? email ?? 'Teacher',
      isActive: true,
    );
  }

  Future<TeacherSignInResult> signInTeacher({
    required String email,
    required String password,
    String? captchaToken,
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
          if (captchaToken != null && captchaToken.isNotEmpty)
            'captcha_token': captchaToken,
        },
        auth: false,
      );

      if (response['mfa_required'] == true) {
        return TeacherSignInResult(
          needsMfa: true,
          mfaTicket: response['mfa_ticket']?.toString(),
          message: response['message']?.toString(),
        );
      }

      if (response['mfa_enrollment_required'] == true) {
        return TeacherSignInResult(
          needsMfaEnrollment: true,
          mfaTicket: response['mfa_ticket']?.toString(),
          message: response['message']?.toString(),
        );
      }

      final account = await _accountFromAuthResponse(response);
      if (account == null) {
        throw const CloudAuthException('Sign in failed. Try again.');
      }

      if (!account.isApproved) {
        await ApiService.clearSession();
        throw const CloudAuthException(
          'Your account is waiting for school admin approval. Ask your COC admin to approve you before signing in.',
        );
      }

      if (!_isEmailVerified(response)) {
        await ApiService.clearSession();
        throw const CloudAuthException(
          'This email has not been confirmed yet. Open the confirmation email, then sign in again.',
        );
      }

      return TeacherSignInResult(account: account);
    } catch (error) {
      if (error is ApiException &&
          (error.captchaRequired || error.statusCode == 429)) {
        return TeacherSignInResult(
          captchaRequired: error.captchaRequired,
          captchaSiteKey: error.captchaSiteKey,
          message: _friendlyApiMessage(error),
        );
      }
      throw CloudAuthException(_friendlyError(error));
    }
  }

  Future<CloudTeacherAccount> completeMfaSignIn({
    required String mfaTicket,
    required String code,
  }) async {
    _ensureApiReady();
    try {
      final response = await ApiService.postJson(
        '/login/mfa',
        <String, dynamic>{
          'mfa_ticket': mfaTicket,
          'code': code.trim(),
          'device_name': 'mobile',
        },
        auth: false,
      );

      final account = await _accountFromAuthResponse(response);
      if (account == null || !account.isApproved) {
        throw const CloudAuthException('Sign in failed after the security code.');
      }
      return account;
    } catch (error) {
      throw CloudAuthException(_friendlyError(error));
    }
  }

  Future<Map<String, String>> beginMfaEnrollmentDuringLogin({
    required String mfaTicket,
  }) async {
    _ensureApiReady();
    final response = await ApiService.postJson(
      '/login/mfa/setup',
      <String, dynamic>{'mfa_ticket': mfaTicket},
      auth: false,
    );
    final secret = response['secret']?.toString();
    final url = response['otpauth_url']?.toString();
    if (secret == null || url == null) {
      throw const CloudAuthException(
        'Could not start two-factor setup. Sign in again.',
      );
    }
    return {'secret': secret, 'otpauth_url': url};
  }

  Future<CloudTeacherAccount> completeMfaEnrollmentDuringLogin({
    required String mfaTicket,
    required String code,
  }) async {
    _ensureApiReady();
    final response = await ApiService.postJson(
      '/login/mfa/enroll',
      <String, dynamic>{
        'mfa_ticket': mfaTicket,
        'code': code.trim(),
        'device_name': 'mobile',
      },
      auth: false,
    );
    final account = await _accountFromAuthResponse(response);
    if (account == null) {
      throw const CloudAuthException('Setup did not finish. Try again.');
    }
    return account;
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

    if (!account.isApproved) {
      await ApiService.clearSession();
      throw const CloudAuthException(
        'Email confirmed. Your account is waiting for school admin approval. Ask your COC admin to approve you, then sign in.',
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
    final accessStatus =
        profileMap['access_status']?.toString() ??
        response['access_status']?.toString() ??
        'approved';
    final school = profileMap['school_name']?.toString();

    await ApiService.setSession(token: token, userId: id, email: email);

    return CloudTeacherAccount(
      id: id,
      email: email,
      name: name == null || name.isEmpty ? email : name,
      isActive: isActive,
      accessStatus: accessStatus,
      school: school,
      department: profileMap['department']?.toString(),
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
    final accessStatus =
        profileMap['access_status']?.toString() ??
        response['access_status']?.toString() ??
        'approved';

    return CloudTeacherAccount(
      id: id,
      email: email,
      name: name == null || name.isEmpty ? email : name,
      isActive: profileMap['is_active'] != false,
      accessStatus: accessStatus,
      school: profileMap['school_name']?.toString(),
      department: profileMap['department']?.toString(),
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

  bool _isAccessPending(Map<String, dynamic> response) {
    if (response['access_pending'] == true) {
      return true;
    }
    final status = response['access_status']?.toString().toLowerCase();
    if (status == 'pending' || status == 'revoked') {
      return true;
    }
    final user = response['user'];
    if (user is Map) {
      final profile = user['profile'];
      if (profile is Map) {
        final profileStatus = profile['access_status']?.toString().toLowerCase();
        if (profileStatus == 'pending' || profileStatus == 'revoked') {
          return true;
        }
      }
    }
    return false;
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
    if (normalized.contains('waiting for school admin') ||
        normalized.contains('admin approval')) {
      return 'Your account is waiting for school admin approval. Ask your COC admin to approve you before signing in.';
    }
    if (normalized.contains('revoked by your school admin')) {
      return 'This account was revoked by your school admin. Contact your COC admin if you need access again.';
    }
    if (normalized.contains('credentials') ||
        normalized.contains('incorrect')) {
      return 'The email or password is incorrect. Check the account details or reset your password.';
    }
    if (normalized.contains('email not confirmed') ||
        normalized.contains('not verified') ||
        normalized.contains('not been confirmed')) {
      return 'This email has not been confirmed yet. Open the confirmation email, then sign in again.';
    }
    if (normalized.contains('already been taken') ||
        normalized.contains('already registered') ||
        normalized.contains('already exists')) {
      return 'An account with this email already exists and is approved. Sign in with your email and password instead.';
    }
    if (normalized.contains('password')) {
      return 'The password does not meet requirements. Use at least 8 characters with a letter, a number, and a symbol (e.g. !@#\$%).';
    }
    if (normalized.contains('rate limit') || normalized.contains('too many')) {
      return 'Too many attempts. Wait a minute, then try again.';
    }
    if (normalized.contains('security check') || normalized.contains('captcha')) {
      return 'Complete the security check on the web portal, then try again.';
    }
    if (normalized.contains('locked') || error.statusCode == 429) {
      return error.message;
    }
    return error.message;
  }
}
