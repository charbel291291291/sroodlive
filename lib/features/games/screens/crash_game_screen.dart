import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class CrashGameScreen extends StatefulWidget {
  const CrashGameScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<CrashGameScreen> createState() => _CrashGameScreenState();
}

class _CrashGameScreenState extends State<CrashGameScreen> {
  late final WebViewController _controller;

  bool _loading = true;
  bool _error = false;
  String? _errorMessage;
  Timer? _loadingTimer;

  static const _gameUrl = 'https://crash-rocket-game-nine.vercel.app';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController();

    if (!kIsWeb && _controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF08060F))
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;

            setState(() {
              _loading = true;
              _error = false;
              _errorMessage = null;
            });

            _startLoadingTimeout();
          },
          onPageFinished: (_) async {
            _loadingTimer?.cancel();

            if (!mounted) return;

            setState(() {
              _loading = false;
            });

            await _injectAuth();
            await _checkBlankPage();
          },
          onWebResourceError: (error) {
            _loadingTimer?.cancel();

            if (!mounted) return;

            setState(() {
              _loading = false;
              _error = true;
              _errorMessage =
                  '${error.errorCode}: ${error.description}';
            });
          },
        ),
      );

    _loadGame();
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  void _startLoadingTimeout() {
    _loadingTimer?.cancel();

    _loadingTimer = Timer(const Duration(seconds: 18), () {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = true;
        _errorMessage = widget.isArabic
            ? '\u0627\u0633\u062a\u063a\u0631\u0642 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0644\u0639\u0628\u0629 \u0648\u0642\u062a\u0627 \u0637\u0648\u064a\u0644\u0627.'
            : 'The game took too long to load.';
      });
    });
  }

  Future<void> _loadGame() async {
    final uri = Uri.parse(_gameUrl).replace(
      queryParameters: {
        'source': 'srood_live',
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    await _controller.loadRequest(uri);
  }

  Future<void> _reloadGame() async {
    setState(() {
      _loading = true;
      _error = false;
      _errorMessage = null;
    });

    await _controller.clearCache();
    await _controller.clearLocalStorage();
    await _loadGame();
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(_gameUrl);

    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _injectAuth() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    final accessToken = session.accessToken.replaceAll("'", r"\'");
    final refreshToken = (session.refreshToken ?? '').replaceAll("'", r"\'");

    await _controller.runJavaScript('''
      (function () {
        window.SROOD_LIVE_WEBVIEW = true;
        window.SROOD_ACCESS_TOKEN = '$accessToken';
        window.SROOD_REFRESH_TOKEN = '$refreshToken';

        var attempts = 0;

        function tryInject() {
          try {
            if (window.__supabase && window.__supabase.auth) {
              window.__supabase.auth.setSession({
                access_token: '$accessToken',
                refresh_token: '$refreshToken'
              });
              return;
            }
          } catch (e) {
            console.log('Srood auth injection failed', e);
          }

          if (attempts < 40) {
            attempts++;
            setTimeout(tryInject, 250);
          }
        }

        tryInject();
      })();
    ''');
  }

  Future<void> _checkBlankPage() async {
    try {
      await Future<void>.delayed(const Duration(seconds: 2));

      final result = await _controller.runJavaScriptReturningResult('''
        (function () {
          var text = document.body ? document.body.innerText.trim() : '';
          var html = document.body ? document.body.innerHTML.trim() : '';
          return JSON.stringify({
            title: document.title || '',
            textLength: text.length,
            htmlLength: html.length,
            url: window.location.href
          });
        })();
      ''');

      final value = result.toString();

      if (!mounted) return;

      if (value.contains('"textLength":0') &&
          value.contains('"htmlLength":0')) {
        setState(() {
          _error = true;
          _errorMessage = widget.isArabic
              ? '\u062a\u0645 \u0641\u062a\u062d \u0627\u0644\u0644\u0639\u0628\u0629 \u0644\u0643\u0646 \u0627\u0644\u0635\u0641\u062d\u0629 \u0641\u0627\u0631\u063a\u0629.'
              : 'The game opened, but the page is blank.';
        });
      }
    } catch (_) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _CrashGameFallback(
        isArabic: widget.isArabic,
        message: widget.isArabic
            ? '\u0627\u0644\u0644\u0639\u0628\u0629 \u062a\u0639\u0645\u0644 \u062f\u0627\u062e\u0644 \u062a\u0637\u0628\u064a\u0642 Android.'
            : 'Crash Rocket works inside the Android app.',
        onRetry: _openInBrowser,
        retryLabel: widget.isArabic
            ? '\u0641\u062a\u062d \u0627\u0644\u0644\u0639\u0628\u0629'
            : 'Open game',
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF08060F),
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            WebViewWidget(controller: _controller),
            if (_loading) _buildLoading(),
            if (_error) _buildError(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: const Color(0xFF08060F),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                color: Color(0xFF8B26D9),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.isArabic
                  ? '\u062c\u0627\u0631\u064a \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0644\u0639\u0628\u0629...'
                  : 'Loading game...',
              style: const TextStyle(
                color: Color(0xFF7A6890),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return _CrashGameFallback(
      isArabic: widget.isArabic,
      message: _errorMessage ??
          (widget.isArabic
              ? '\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0644\u0639\u0628\u0629.'
              : 'Failed to load game.'),
      onRetry: _reloadGame,
      retryLabel: widget.isArabic
          ? '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629'
          : 'Retry',
      onOpenBrowser: _openInBrowser,
    );
  }
}

class _CrashGameFallback extends StatelessWidget {
  const _CrashGameFallback({
    required this.isArabic,
    required this.message,
    required this.onRetry,
    required this.retryLabel,
    this.onOpenBrowser,
  });

  final bool isArabic;
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;
  final VoidCallback? onOpenBrowser;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF08060F),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF1B102A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF4A3470)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.rocket_launch_rounded,
                color: Color(0xFFF0C15A),
                size: 54,
              ),
              const SizedBox(height: 16),
              const Text(
                'Crash Rocket',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFD8CFEA),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B26D9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(retryLabel),
                ),
              ),
              if (onOpenBrowser != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onOpenBrowser,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF0C15A),
                      side: const BorderSide(color: Color(0xFF4A3470)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      isArabic
                          ? '\u0641\u062a\u062d \u0641\u064a \u0627\u0644\u0645\u062a\u0635\u0641\u062d'
                          : 'Open in browser',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
