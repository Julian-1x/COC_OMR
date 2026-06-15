import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Optional crash reporting via Sentry.
///
/// Pass at build time:
/// `--dart-define=SENTRY_DSN=https://...@sentry.io/...`
/// Optional: `--dart-define=SENTRY_ENVIRONMENT=production`
class CrashReportingService {
  CrashReportingService._();

  static const String _dsn = String.fromEnvironment('SENTRY_DSN');
  static const String _environment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: 'production',
  );

  static bool get isConfigured => _dsn.isNotEmpty;

  static Future<void> initAndRun(void Function() appRunner) async {
    if (!isConfigured) {
      appRunner();
      return;
    }

    await SentryFlutter.init(
      (options) {
        options.dsn = _dsn;
        options.environment = _environment;
        options.tracesSampleRate = kReleaseMode ? 0.2 : 1.0;
        options.sendDefaultPii = false;
      },
      appRunner: appRunner,
    );
  }

  static Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
    String? hint,
  }) async {
    if (!isConfigured) {
      return;
    }
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      hint: hint == null ? null : Hint.withMap({'hint': hint}),
    );
  }
}
