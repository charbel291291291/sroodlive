import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'spin_wheel_screen.dart';

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

  // Standard Android Chrome user-agent — avoids WebView detection blocks
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    _initController();
    _loadGame();
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  void _initController() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Create with Android-specific params so platform settings take effect immediately
      final androidParams = AndroidWebViewControllerCreationParams();
      _controller = WebViewController.fromPlatformCreationParams(androidParams);

      AndroidWebViewController.enableDebugging(true);
      final androidCtrl = _controller.platform as AndroidWebViewController;
      androidCtrl.setMediaPlaybackRequiresUserGesture(false);
    } else {
      _controller = WebViewController();
    }

    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF08060F))
      ..setUserAgent(_userAgent)
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
            setState(() => _loading = false);
            await _injectAuth();
            await _checkBlankPage();
          },
          onWebResourceError: (error) {
            // Ignore sub-resource errors (ads, trackers) — only care about main frame
            if (error.isForMainFrame == false) return;
            _loadingTimer?.cancel();
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = true;
              _errorMessage = '${error.errorCode}: ${error.description}';
            });
          },
        ),
      );
  }

  void _startLoadingTimeout() {
    _loadingTimer?.cancel();
    _loadingTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
        _errorMessage = widget.isArabic
            ? 'استغرق تحميل اللعبة وقتاً طويلاً.'
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
    await _controller.loadRequest(
      uri,
      headers: {
        'Accept-Language': 'en-US,en;q=0.9',
        'Cache-Control': 'no-cache',
      },
    );
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
    await launchUrl(Uri.parse(_gameUrl), mode: LaunchMode.externalApplication);
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
          if (attempts < 40) { attempts++; setTimeout(tryInject, 250); }
        }
        tryInject();
      })();
    ''');
  }

  Future<void> _checkBlankPage() async {
    try {
      // Wait longer so React/Vite can fully hydrate on slower devices
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted) return;

      final result = await _controller.runJavaScriptReturningResult('''
        (function () {
          var body = document.body;
          return JSON.stringify({
            title: document.title || '',
            textLength: body ? body.innerText.trim().length : 0,
            htmlLength: body ? body.innerHTML.trim().length : 0,
            url: window.location.href
          });
        })();
      ''');

      if (!mounted) return;
      final value = result.toString();

      // Extract htmlLength value from the JSON string
      final htmlLengthMatch = RegExp(r'"htmlLength":(\d+)').firstMatch(value);
      final htmlLength = int.tryParse(htmlLengthMatch?.group(1) ?? '0') ?? 0;

      // Only flag as blank if HTML is truly empty (< 50 chars means
      // nothing rendered — React root with content is always much larger)
      if (htmlLength < 50) {
        setState(() {
          _error = true;
          _errorMessage = widget.isArabic
              ? 'تم فتح اللعبة لكن الصفحة فارغة.'
              : 'The game opened, but the page is blank.';
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _CrashGameFallback(
        isArabic: widget.isArabic,
        message: widget.isArabic
            ? 'اللعبة تعمل داخل تطبيق Android.'
            : 'Crash Rocket works inside the Android app.',
        onRetry: _openInBrowser,
        retryLabel: widget.isArabic ? 'فتح اللعبة' : 'Open game',
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
            if (!_loading && !_error) _buildSpinShortcut(),
          ],
        ),
      ),
    );
  }

  Widget _buildSpinShortcut() {
    final isArabic = widget.isArabic;
    return Positioned(
      top: 8,
      right: isArabic ? null : 12,
      left: isArabic ? 12 : null,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SpinWheelScreen(isArabic: isArabic),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF1B0D2A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFF8B26D9).withValues(alpha: 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B26D9).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('\u{1F3A1}', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 5),
              Text(
                isArabic ? 'عجلة الحظ' : 'Spin Wheel',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
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
              widget.isArabic ? 'جاري تحميل اللعبة...' : 'Loading game...',
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
      message:
          _errorMessage ??
          (widget.isArabic ? 'تعذر تحميل اللعبة.' : 'Failed to load game.'),
      onRetry: _reloadGame,
      retryLabel: widget.isArabic ? 'إعادة المحاولة' : 'Retry',
      onOpenBrowser: _openInBrowser,
    );
  }
}

// ---------------------------------------------------------------------------

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
                      isArabic ? 'فتح في المتصفح' : 'Open in browser',
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
