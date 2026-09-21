import 'package:flutter/material.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Cloudflare Turnstile for sign-in / register on mobile.
///
/// Turnstile only trusts origins configured in Cloudflare (omrweb.vercel.app).
/// We load HTML with that base URL so the WebView origin matches the widget.
class TurnstileCaptchaField extends StatefulWidget {
  const TurnstileCaptchaField({
    super.key,
    required this.siteKey,
    required this.onToken,
    this.webBaseUrl,
  });

  final String siteKey;
  final ValueChanged<String?> onToken;

  /// School web portal origin (must match Cloudflare Turnstile hostnames).
  final String? webBaseUrl;

  @override
  State<TurnstileCaptchaField> createState() => _TurnstileCaptchaFieldState();
}

class _TurnstileCaptchaFieldState extends State<TurnstileCaptchaField> {
  late final WebViewController _controller;
  bool _loadError = false;
  bool _ready = false;
  int _generation = 0;

  String get _normalizedWebBase {
    final raw = widget.webBaseUrl ?? ApiService.webBaseUrl;
    return raw.replaceAll(RegExp(r'/$'), '');
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _ready = true);
            }
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _loadError = true;
                _ready = false;
              });
              widget.onToken(null);
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'TurnstileChannel',
        onMessageReceived: (message) {
          final token = message.message.trim();
          if (token == 'error') {
            if (mounted) {
              setState(() => _loadError = true);
            }
            widget.onToken(null);
            return;
          }
          if (mounted) {
            setState(() {
              _loadError = false;
              _ready = true;
            });
          }
          widget.onToken(token.isEmpty ? null : token);
        },
      );
    _loadCaptcha();
  }

  @override
  void didUpdateWidget(covariant TurnstileCaptchaField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteKey != widget.siteKey ||
        oldWidget.webBaseUrl != widget.webBaseUrl) {
      _loadCaptcha();
    }
  }

  void _loadCaptcha() {
    setState(() {
      _loadError = false;
      _ready = false;
    });
    widget.onToken(null);
    _generation += 1;
    _controller.loadHtmlString(
      _html(widget.siteKey, _generation),
      baseUrl: '$_normalizedWebBase/',
    );
  }

  String _html(String siteKey, int generation) {
    final escapedKey = siteKey.replaceAll("'", r"\'");
    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer></script>
<style>body{margin:0;padding:4px;background:#fff;}</style>
</head>
<body>
<div id="turnstile-$generation"></div>
<script>
function renderTurnstile() {
  if (typeof turnstile === 'undefined') {
    setTimeout(renderTurnstile, 120);
    return;
  }
  turnstile.render('#turnstile-$generation', {
    sitekey: '$escapedKey',
    theme: 'light',
    callback: function(token) { TurnstileChannel.postMessage(token); },
    'expired-callback': function() { TurnstileChannel.postMessage(''); },
    'error-callback': function() { TurnstileChannel.postMessage('error'); }
  });
}
renderTurnstile();
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Security check',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.brandMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Tick the box below, then tap Create Account.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.brandMuted,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: Colors.white,
            child: SizedBox(
              height: 80,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  WebViewWidget(controller: _controller),
                  if (!_ready && !_loadError)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_loadError) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Security check could not load. Check your internet, then tap Retry.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _loadCaptcha,
              child: const Text('Retry security check'),
            ),
          ),
        ],
      ],
    );
  }
}
