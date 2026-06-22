import 'package:flutter/foundation.dart';
import 'package:omr_app/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PinSyncException implements Exception {
  const PinSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CloudPinCredentials {
  const CloudPinCredentials({
    required this.pinHash,
    required this.pinSalt,
    required this.name,
    this.school,
    this.email,
    this.cloudUserId,
  });

  final String pinHash;
  final String pinSalt;
  final String name;
  final String? school;
  final String? email;
  final String? cloudUserId;
}

class TeacherPinSyncService {
  TeacherPinSyncService._();

  static final TeacherPinSyncService instance = TeacherPinSyncService._();

  Future<CloudPinCredentials?> fetchForCurrentUser() async {
    final client = SupabaseService.client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) {
      return null;
    }

    try {
      final row = await client
          .from('teacher_profiles')
          .select('pin_hash, pin_salt, full_name, school_name')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        return null;
      }

      final pinHash = (row['pin_hash'] as String?)?.trim();
      final pinSalt = (row['pin_salt'] as String?)?.trim();
      final name = (row['full_name'] as String?)?.trim();
      if (pinHash == null ||
          pinHash.isEmpty ||
          pinSalt == null ||
          pinSalt.isEmpty ||
          name == null ||
          name.isEmpty) {
        return null;
      }

      final user = client.auth.currentUser;
      return CloudPinCredentials(
        pinHash: pinHash,
        pinSalt: pinSalt,
        name: name,
        school: (row['school_name'] as String?)?.trim(),
        email: user?.email?.trim().toLowerCase(),
        cloudUserId: userId,
      );
    } catch (error) {
      debugPrint('Failed to fetch cloud PIN credentials: $error');
      return null;
    }
  }

  Future<void> uploadPin({
    required String pinHash,
    required String pinSalt,
  }) async {
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    final userId = user?.id;
    if (client == null || userId == null) {
      throw const PinSyncException(
        'Sign in online before saving your PIN to the cloud.',
      );
    }

    final timestamp = DateTime.now().toUtc().toIso8601String();
    final pinPayload = <String, Object?>{
      'pin_hash': pinHash,
      'pin_salt': pinSalt,
      'updated_at': timestamp,
    };

    try {
      final updated = await client
          .from('teacher_profiles')
          .update(pinPayload)
          .eq('id', userId)
          .select('id')
          .maybeSingle();

      if (updated != null) {
        return;
      }

      final metadata = user?.userMetadata ?? const <String, dynamic>{};
      final fullName = (metadata['full_name'] as String?)?.trim() ??
          user?.email?.trim() ??
          'Teacher';
      final school = (metadata['school'] as String?)?.trim();

      await client.from('teacher_profiles').upsert({
        'id': userId,
        'full_name': fullName,
        'school_name': school == null || school.isEmpty ? null : school,
        'role': 'teacher',
        'is_active': true,
        ...pinPayload,
      });
    } on PostgrestException catch (error) {
      throw PinSyncException(_friendlyPinUploadError(error));
    } catch (error) {
      debugPrint('Failed to upload cloud PIN credentials: $error');
      rethrow;
    }
  }

  String _friendlyPinUploadError(PostgrestException error) {
    final message = error.message.toLowerCase();
    if (message.contains('pin_hash') ||
        message.contains('pin_salt') ||
        error.code == '42703') {
      return 'Cloud PIN backup is not enabled on the school server yet. '
          'Your PIN works on this phone — ask IT to run the latest database update.';
    }
    if (message.contains('row-level security') ||
        message.contains('permission denied')) {
      return 'Could not save PIN to your account. Sign out, sign in again on Wi‑Fi, then retry.';
    }
    return 'Could not back up PIN to the cloud. Check Wi‑Fi and try again from Settings.';
  }

  Future<void> syncLocalPinIfMissing({
    required Future<({String hash, String salt})?> Function() readLocal,
  }) async {
    if (!SupabaseService.hasActiveSession) {
      return;
    }

    final local = await readLocal();
    if (local == null) {
      return;
    }

    final cloud = await fetchForCurrentUser();
    if (cloud != null) {
      return;
    }

    try {
      await uploadPin(pinHash: local.hash, pinSalt: local.salt);
    } catch (error) {
      debugPrint('Background PIN sync skipped: $error');
    }
  }
}
