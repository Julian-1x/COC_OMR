import 'package:flutter/foundation.dart';
import 'package:omr_app/constants/auth_config.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/supabase_service.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class CloudAuthService {
  CloudAuthService._();

  static final CloudAuthService instance = CloudAuthService._();

  Future<CloudTeacherAccount> registerTeacher({
    required String name,
    required String email,
    required String password,
    required String school,
  }) async {
    final client = _clientOrThrow();
    final trimmedName = name.trim();
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final response = await client.auth.signUp(
        email: normalizedEmail,
        password: password,
        emailRedirectTo: kAuthRedirectUrl,
        data: {
          'full_name': trimmedName,
          'school': school.trim(),
          'role': 'teacher',
        },
      );
      final user = response.user;
      if (user == null) {
        throw const CloudAuthException(
          'Registration started. Check the teacher email to confirm the account, then sign in.',
        );
      }

      if (response.session == null) {
        throw const CloudAuthException(
          'Account created. Open the confirmation email on this phone, tap the link, then return to the app and tap Login.',
        );
      }

      await _upsertTeacherProfile(
        client: client,
        userId: user.id,
        fullName: trimmedName,
        school: school.trim(),
      );

      return CloudTeacherAccount(
        id: user.id,
        email: normalizedEmail,
        name: trimmedName,
        isActive: true,
      );
    } catch (error) {
      throw CloudAuthException(_friendlyError(error));
    }
  }

  Future<void> signOut() async {
    await LocalAuthService.instance.lock();
    final client = SupabaseService.client;
    if (client != null) {
      await client.auth.signOut();
    }
    await LocalDataStore.instance.clearMemoryOnAuthReset();
  }

  Future<CloudTeacherAccount?> accountFromCurrentSession() async {
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return null;
    }

    try {
      final profile = await _loadOrCreateTeacherProfile(
        client: client,
        user: user,
        fallbackEmail: user.email ?? '',
      );
      final profileName = (profile['full_name'] as String?)?.trim();
      final email = user.email ?? '';
      return CloudTeacherAccount(
        id: user.id,
        email: email,
        name: profileName == null || profileName.isEmpty ? email : profileName,
        isActive: profile['is_active'] != false,
      );
    } catch (error) {
      debugPrint('Failed to resolve session account: $error');
      return CloudTeacherAccount(
        id: user.id,
        email: user.email ?? '',
        name: user.email ?? 'Teacher',
        isActive: true,
      );
    }
  }

  Future<CloudTeacherAccount> signInTeacher({
    required String email,
    required String password,
  }) async {
    final client = _clientOrThrow();
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final response = await client.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw const CloudAuthException('Sign in failed. Try again.');
      }

      final profile = await _loadOrCreateTeacherProfile(
        client: client,
        user: user,
        fallbackEmail: normalizedEmail,
      );

      final isActive = profile['is_active'] != false;
      if (!isActive) {
        throw const CloudAuthException(
          'This teacher account is disabled. Ask the admin to reactivate it.',
        );
      }

      final profileName = (profile['full_name'] as String?)?.trim();
      return CloudTeacherAccount(
        id: user.id,
        email: normalizedEmail,
        name: profileName == null || profileName.isEmpty
            ? normalizedEmail
            : profileName,
        isActive: isActive,
      );
    } catch (error) {
      throw CloudAuthException(_friendlyError(error));
    }
  }

  Future<Map<String, dynamic>> _loadOrCreateTeacherProfile({
    required SupabaseClient client,
    required User user,
    required String fallbackEmail,
  }) async {
    final profile = await client
        .from('teacher_profiles')
        .select('full_name, is_active')
        .eq('id', user.id)
        .maybeSingle();

    if (profile != null) {
      return profile;
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final metadataName = (metadata['full_name'] as String?)?.trim();
    final profileName = metadataName == null || metadataName.isEmpty
        ? fallbackEmail
        : metadataName;

    await _upsertTeacherProfile(
      client: client,
      userId: user.id,
      fullName: profileName,
    );

    return <String, dynamic>{
      'full_name': profileName,
      'is_active': true,
    };
  }

  Future<void> _upsertTeacherProfile({
    required SupabaseClient client,
    required String userId,
    required String fullName,
    String? school,
  }) async {
    await client.from('teacher_profiles').upsert({
      'id': userId,
      'full_name': fullName,
      'school_name':
          school == null || school.trim().isEmpty ? null : school.trim(),
      'role': 'teacher',
      'is_active': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  SupabaseClient _clientOrThrow() {
    final client = SupabaseService.client;
    if (client == null) {
      throw const CloudAuthException(
        'Supabase is not connected. Start the app with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.',
      );
    }
    return client;
  }

  String _friendlyError(Object error) {
    if (error is CloudAuthException) {
      return error.message;
    }
    if (error is AuthException) {
      return _friendlyAuthMessage(error.message);
    }
    if (error is PostgrestException) {
      return _friendlyDatabaseMessage(error.message);
    }

    return _friendlyNetworkMessage(error.toString());
  }

  String _friendlyAuthMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('invalid login credentials')) {
      return 'The email or password is incorrect. Check the account details or reset the password in Supabase.';
    }
    if (normalized.contains('email not confirmed')) {
      return 'This email has not been confirmed yet. Open the confirmation email, then sign in again.';
    }
    if (normalized.contains('user already registered') ||
        normalized.contains('already been registered')) {
      return 'An account with this email already exists. Use Login instead.';
    }
    if (normalized.contains('password')) {
      return 'The password does not meet Supabase requirements. Use at least 6 characters.';
    }
    if (normalized.contains('rate limit') || normalized.contains('too many')) {
      return 'Too many attempts. Wait a minute, then try again.';
    }
    return message;
  }

  String _friendlyDatabaseMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('permission') ||
        normalized.contains('row-level security') ||
        normalized.contains('violates row-level security')) {
      return 'Registration blocked by database rules. In Supabase, run supabase/fix_registration.sql, then try Login (not Register again).';
    }
    return message;
  }

  String _friendlyNetworkMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('failed to fetch') ||
        normalized.contains('xmlhttprequest') ||
        normalized.contains('clientexception') ||
        normalized.contains('socketexception') ||
        normalized.contains('failed host lookup')) {
      return 'Could not reach Supabase. Check your internet connection and the Supabase project URL.';
    }
    return message.replaceFirst(
        RegExp(r'^(exception|clientexception):\s*', caseSensitive: false), '');
  }
}
