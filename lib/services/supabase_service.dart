import 'package:flutter/foundation.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static const String _url = String.fromEnvironment('SUPABASE_URL');
  static const String _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const String _legacyAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static bool _isConfigured = false;
  static bool _isReady = false;

  static bool get isConfigured => _isConfigured;
  static bool get isReady => _isReady;
  static String? get currentUserId =>
      client?.auth.currentUser?.id ??
      LocalAuthService.instance.activeCloudUserId;

  static bool get hasActiveSession =>
      client?.auth.currentSession != null;

  static String get _clientKey =>
      _publishableKey.isNotEmpty ? _publishableKey : _legacyAnonKey;

  static SupabaseClient? get client {
    if (!_isReady) {
      return null;
    }
    return Supabase.instance.client;
  }

  static Future<void> init() async {
    _isConfigured = _url.isNotEmpty && _clientKey.isNotEmpty;
    if (!_isConfigured) {
      debugPrint(
        'Supabase not configured. Pass SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY with --dart-define.',
      );
      return;
    }

    try {
      await Supabase.initialize(
        url: _url,
        anonKey: _clientKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      _isReady = true;
    } catch (error) {
      debugPrint('Supabase init failed: $error');
      _isReady = false;
    }
  }
}
