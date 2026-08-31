import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Cloudflare Turnstile widget for sign-in / register on mobile.
class TurnstileCaptchaField extends StatefulWidget {
  const TurnstileCaptchaField({
    super.key,
    required this.siteKey,
    required this.onToken,
  });

  final String siteKey;
  final ValueChanged<String?> onToken;

  @override
  State<TurnstileCaptchaField> createState() => _TurnstileCaptchaFieldState();
}

class _TurnstileCaptchaFieldState extends State<TurnstileCaptchaField> {
  late final WebViewController _controller;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'TurnstileChannel',
        onMessageReceived: (message) {
          final token = message.message.trim();
          widget.onToken(token.isEmpty ? null : token);
        },
      );
    _loadHtml();
  }

  @override
  void didUpdateWidget(covariant TurnstileCaptchaField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteKey != widget.siteKey) {
      _loadHtml();
    }
  }

  void _loadHtml() {
    _generation += 1;
    final generation = _generation;
    widget.onToken(null);
    _controller.loadHtmlString(_html(widget.siteKey, generation));
  }

  String _html(String siteKey, int generation) {
    final escapedKey = siteKey.replaceAll("'", r"\'");
    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer></script>
<style>body{margin:0;padding:4px;background:transparent;}</style>
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
    'error-callback': function() { TurnstileChannel.postMessage(''); }
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 78,
        width: double.infinity,
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
