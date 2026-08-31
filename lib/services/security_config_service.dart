import 'package:omr_app/services/api_service.dart';

class SecurityConfig {
  const SecurityConfig({
    required this.captchaEnabled,
    this.captchaSiteKey,
    this.mfaAvailable = true,
  });

  final bool captchaEnabled;
  final String? captchaSiteKey;
  final bool mfaAvailable;

  static const SecurityConfig disabled = SecurityConfig(captchaEnabled: false);
}

class SecurityConfigService {
  SecurityConfigService._();

  static final SecurityConfigService instance = SecurityConfigService._();

  SecurityConfig? _cached;

  Future<SecurityConfig> fetch({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) {
      return _cached!;
    }
    if (!ApiService.isConfigured) {
      return SecurityConfig.disabled;
    }

    try {
      final response = await ApiService.getJson(
        '/auth/security-config',
        auth: false,
      );
      final config = SecurityConfig(
        captchaEnabled: response['captcha_enabled'] == true,
        captchaSiteKey: response['captcha_site_key']?.toString(),
        mfaAvailable: response['mfa_available'] != false,
      );
      _cached = config;
      return config;
    } catch (_) {
      return _cached ?? SecurityConfig.disabled;
    }
  }

  void clearCache() => _cached = null;
}
