import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:omr_app/services/local_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.sessionInvalidated = false,
    this.isNetworkError = false,
    this.captchaRequired = false,
    this.captchaSiteKey,
  });

  final String message;
  final int? statusCode;
  final bool sessionInvalidated;

  /// True when the server was never reached (offline, DNS, timeout).
  /// Callers must not treat this as an account problem.
  final bool isNetworkError;

  /// Server asked for a CAPTCHA before retrying (Cloudflare Turnstile).
  final bool captchaRequired;
  final String? captchaSiteKey;

  @override
  String toString() => message;
}

/// HTTP client for the Laravel school API (replaces Supabase direct access).
class ApiService {
  ApiService._();

  static const String _baseUrl = String.fromEnvironment('API_BASE_URL');

  static const String _tokenKey = 'api_auth_token';
  static const String _userIdKey = 'api_user_id';
  static const String _emailKey = 'api_user_email';

  static String? _token;
  static String? _cachedUserId;
  static String? _cachedEmail;

  static bool get isConfigured => _normalizedBaseUrl.isNotEmpty;
  static bool get isReady => isConfigured;
  static bool get hasActiveSession =>
      _token != null && _token!.trim().isNotEmpty;
  static String? get currentUserId =>
      _cachedUserId ?? LocalAuthService.instance.activeCloudUserId;
  static String? get currentEmail => _cachedEmail;

  static String get _normalizedBaseUrl {
    final trimmed = _baseUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  static Future<void> init() async {
    if (!isConfigured) {
      debugPrint(
        'API not configured. Pass API_BASE_URL with --dart-define or secrets.json.',
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _cachedUserId = prefs.getString(_userIdKey);
    _cachedEmail = prefs.getString(_emailKey);
  }

  static Future<void> setSession({
    required String token,
    required String userId,
    String? email,
  }) async {
    _token = token;
    _cachedUserId = userId;
    _cachedEmail = email?.trim().toLowerCase();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, userId);
    if (_cachedEmail != null) {
      await prefs.setString(_emailKey, _cachedEmail!);
    } else {
      await prefs.remove(_emailKey);
    }
  }

  static Future<void> clearSession() async {
    _token = null;
    _cachedUserId = null;
    _cachedEmail = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_emailKey);
  }

  static Future<Map<String, dynamic>> getJson(
    String path, {
    bool auth = true,
  }) async {
    return _request('GET', path, auth: auth);
  }

  static Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    return _request('POST', path, body: body, auth: auth);
  }

  static Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    return _request('PUT', path, body: body, auth: auth);
  }

  static Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    return _request('PATCH', path, body: body, auth: auth);
  }

  static Future<void> deleteJson(
    String path, {
    bool auth = true,
  }) async {
    await _request('DELETE', path, auth: auth);
  }

  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Duration _authRequestTimeout = Duration(seconds: 45);
  static const Duration _mfaRequestTimeout = Duration(seconds: 90);

  static bool _isAuthBootstrapPath(String path) =>
      path == '/login' ||
      path == '/register' ||
      path.startsWith('/login/mfa');

  static bool _isRetryableStatus(int status) =>
      status == 502 || status == 503 || status == 504;

  /// Wakes free-tier cloud hosts (Render) before login/register/MFA.
  static Future<void> _wakeSchoolApi() async {
    final uri = Uri.parse('$_normalizedBaseUrl/up');
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await http.get(uri).timeout(const Duration(seconds: 25));
        return;
      } catch (_) {
        if (attempt + 1 < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 2000));
        }
      }
    }
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    _ensureConfigured();

    final isAuthBootstrap = !auth && _isAuthBootstrapPath(path);
    if (isAuthBootstrap) {
      await _wakeSchoolApi();
    }

    final isMfaPath = !auth && path.startsWith('/login/mfa');
    final timeout = isMfaPath
        ? _mfaRequestTimeout
        : isAuthBootstrap
            ? _authRequestTimeout
            : _requestTimeout;
    final maxAttempts = isAuthBootstrap ? 4 : 1;
    ApiException? lastError;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 2500));
      }

      final uri = Uri.parse('$_normalizedBaseUrl/api$path');
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      if (_normalizedBaseUrl.contains('loca.lt')) {
        headers['Bypass-Tunnel-Reminder'] = 'true';
      }

      if (auth) {
        final token = _token;
        if (token == null || token.isEmpty) {
          throw const ApiException('Sign in before using cloud features.');
        }
        headers['Authorization'] = 'Bearer $token';
      }

      late http.Response response;
      try {
        final Future<http.Response> request;
        switch (method) {
          case 'GET':
            request = http.get(uri, headers: headers);
          case 'POST':
            request = http.post(
              uri,
              headers: headers,
              body: jsonEncode(body ?? const <String, dynamic>{}),
            );
          case 'PUT':
            request = http.put(
              uri,
              headers: headers,
              body: jsonEncode(body ?? const <String, dynamic>{}),
            );
          case 'PATCH':
            request = http.patch(
              uri,
              headers: headers,
              body: jsonEncode(body ?? const <String, dynamic>{}),
            );
          case 'DELETE':
            request = http.delete(uri, headers: headers);
          default:
            throw ApiException('Unsupported method: $method');
        }
        response = await request.timeout(timeout);
      } catch (error) {
        if (error is ApiException) {
          rethrow;
        }
        lastError = ApiException(
          _friendlyNetworkMessage(error.toString()),
          isNetworkError: true,
        );
        continue;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) {
          return const <String, dynamic>{};
        }
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return const <String, dynamic>{};
      }

      final sessionInvalidated = auth && response.statusCode == 401;
      if (sessionInvalidated) {
        await clearSession();
      }

      final apiError = ApiException(
        _parseErrorMessage(response),
        statusCode: response.statusCode,
        sessionInvalidated: sessionInvalidated,
        captchaRequired: _captchaRequired(response),
        captchaSiteKey: _captchaSiteKey(response),
      );

      if (_isRetryableStatus(response.statusCode) && attempt + 1 < maxAttempts) {
        lastError = apiError;
        continue;
      }

      throw apiError;
    }

    throw lastError ??
        const ApiException(
          'Could not reach the school server. Check your internet connection.',
          isNetworkError: true,
        );
  }

  static void _ensureConfigured() {
    if (!isConfigured) {
      throw const ApiException(
        'School server is not configured. Reinstall the app with API_BASE_URL.',
      );
    }
  }

  static String _parseErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message;
        }
        final errors = decoded['errors'];
        if (errors is Map) {
          for (final entry in errors.entries) {
            final value = entry.value;
            if (value is List && value.isNotEmpty) {
              return value.first.toString();
            }
          }
        }
      }
    } catch (_) {
      // Fall through to status-based message.
    }

    if (response.statusCode == 502 || response.statusCode == 504) {
      return 'School server is waking up. Wait about a minute and try again.';
    }
    if (response.statusCode == 503) {
      return 'School server is busy. Try again in a moment.';
    }
    if (response.statusCode == 401) {
      return 'Sign in again — your session expired.';
    }
    if (response.statusCode == 403) {
      return 'This action is not allowed for your account.';
    }
    if (response.statusCode == 422) {
      return 'Check the form and try again.';
    }
    if (response.statusCode == 429) {
      return 'Too many attempts. Wait a minute, then try again.';
    }
    return 'Server error (${response.statusCode}). Try again later.';
  }

  static bool _captchaRequired(http.Response response) {
    final decoded = _tryDecodeJson(response.body);
    return decoded?['captcha_required'] == true;
  }

  static String? _captchaSiteKey(http.Response response) {
    final decoded = _tryDecodeJson(response.body);
    final key = decoded?['captcha_site_key'];
    return key is String && key.isNotEmpty ? key : null;
  }

  static Map<String, dynamic>? _tryDecodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  static String _friendlyNetworkMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('timeout') ||
        normalized.contains('timed out')) {
      return 'School server is waking up. Wait about a minute and try again, or turn off Wi‑Fi to unlock with your PIN.';
    }
    if (normalized.contains('socketexception') ||
        normalized.contains('failed host lookup') ||
        normalized.contains('clientexception') ||
        normalized.contains('connection refused') ||
        normalized.contains('network')) {
      return 'Could not reach the school server. Check your internet connection.';
    }
    return message.replaceFirst(
      RegExp(r'^(exception|clientexception):\s*', caseSensitive: false),
      '',
    );
  }
}
