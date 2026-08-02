import 'package:flutter/foundation.dart';
import 'package:omr_app/services/api_service.dart';

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
    final userId = ApiService.currentUserId;
    if (!ApiService.hasActiveSession || userId == null) {
      return null;
    }

    try {
      final response = await ApiService.getJson('/profile/pin');
      final pinHash = (response['pin_hash'] as String?)?.trim();
      final pinSalt = (response['pin_salt'] as String?)?.trim();
      final name = (response['full_name'] as String?)?.trim();
      if (pinHash == null ||
          pinHash.isEmpty ||
          pinSalt == null ||
          pinSalt.isEmpty ||
          name == null ||
          name.isEmpty) {
        return null;
      }

      return CloudPinCredentials(
        pinHash: pinHash,
        pinSalt: pinSalt,
        name: name,
        school: (response['school_name'] as String?)?.trim(),
        email: ApiService.currentEmail,
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
    if (!ApiService.hasActiveSession) {
      throw const PinSyncException(
        'Sign in online before saving your PIN to the cloud.',
      );
    }

    try {
      await ApiService.putJson('/profile/pin', <String, dynamic>{
        'pin_hash': pinHash,
        'pin_salt': pinSalt,
      });
    } on ApiException catch (error) {
      throw PinSyncException(_friendlyPinUploadError(error));
    } catch (error) {
      debugPrint('Failed to upload cloud PIN credentials: $error');
      rethrow;
    }
  }

  String _friendlyPinUploadError(ApiException error) {
    final message = error.message.toLowerCase();
    if (message.contains('pin_hash') || message.contains('pin_salt')) {
      return 'Cloud PIN backup is not enabled on the school server yet. '
          'Your PIN works on this phone — ask IT to run the latest database update.';
    }
    if (message.contains('permission') || error.statusCode == 403) {
      return 'Could not save PIN to your account. Sign out, sign in again on Wi‑Fi, then retry.';
    }
    return 'Could not back up PIN to the cloud. Check Wi‑Fi and try again from Settings.';
  }

  Future<void> syncLocalPinIfMissing({
    required Future<({String hash, String salt})?> Function() readLocal,
  }) async {
    if (!ApiService.hasActiveSession) {
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
