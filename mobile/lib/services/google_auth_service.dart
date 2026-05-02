// Google OAuth2 via PKCE + loopback HTTP server.
//
// Works on Android (Chrome opens auth URL, redirects to 127.0.0.1:18642 which
// our server catches) and Linux/macOS/Windows (same flow in system browser).
// No google-services.json or firebase setup required — just a Google Cloud
// "Desktop app" OAuth2 client ID.
//
// Setup in Google Cloud Console:
//   APIs & Services → Credentials → Create → OAuth 2.0 Client → Desktop app
//   (No redirect URI to add — Google automatically allows 127.0.0.1 for Desktop)
//   Enable: "Tasks API" under APIs & Services → Library.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'settings_service.dart';

class GoogleAuthService {
  static const _port = 18642;
  static const _redirectUri = 'http://127.0.0.1:$_port';
  static const _scope = 'https://www.googleapis.com/auth/tasks';
  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _userinfoEndpoint =
      'https://www.googleapis.com/oauth2/v2/userinfo';

  // ── Public API ─────────────────────────────────────────────────────────────

  // Opens browser, runs PKCE flow, stores tokens.
  // Returns account email on success, null on failure/cancel.
  Future<String?> authorize(String clientId) async {
    final verifier = _codeVerifier();
    final challenge = _codeChallenge(verifier);
    final state = _randomBase64(8);

    final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': _redirectUri,
      'response_type': 'code',
      'scope': _scope,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent',
    });

    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);

      final req = await server.first.timeout(const Duration(minutes: 3));
      _respondOk(req);

      final code = req.uri.queryParameters['code'];
      final returnedState = req.uri.queryParameters['state'];
      if (code == null || returnedState != state) return null;

      final tokens = await _exchangeCode(clientId, code, verifier);
      if (tokens == null) return null;

      await _storeTokens(tokens);
      return await _fetchEmail(tokens.accessToken);
    } catch (_) {
      return null;
    } finally {
      server?.close();
    }
  }

  // Returns a valid access token, refreshing if within 60 s of expiry.
  Future<String?> getAccessToken(String clientId) async {
    final expiry = await SettingsService.getGoogleTokenExpiry();
    if (DateTime.now().millisecondsSinceEpoch < expiry - 60000) {
      return SettingsService.getGoogleAccessToken();
    }
    return _refresh(clientId);
  }

  Future<void> signOut() async {
    await SettingsService.clearGoogleTokens();
  }

  Future<bool> get isConnected async {
    final rt = await SettingsService.getGoogleRefreshToken();
    return rt != null && rt.isNotEmpty;
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<_Tokens?> _exchangeCode(
      String clientId, String code, String verifier) async {
    final res = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
        'client_id': clientId,
        'redirect_uri': _redirectUri,
      },
    );
    if (res.statusCode != 200) return null;
    final d = jsonDecode(res.body) as Map<String, dynamic>;
    if (d['access_token'] == null) return null;
    return _Tokens(
      accessToken: d['access_token'] as String,
      refreshToken: d['refresh_token'] as String?,
      expiresAt: DateTime.now().millisecondsSinceEpoch +
          ((d['expires_in'] as int? ?? 3600) * 1000),
    );
  }

  Future<String?> _refresh(String clientId) async {
    final rt = await SettingsService.getGoogleRefreshToken();
    if (rt == null || rt.isEmpty) return null;
    final res = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': rt,
        'client_id': clientId,
      },
    );
    if (res.statusCode != 200) return null;
    final d = jsonDecode(res.body) as Map<String, dynamic>;
    final at = d['access_token'] as String?;
    if (at == null) return null;
    final exp = DateTime.now().millisecondsSinceEpoch +
        ((d['expires_in'] as int? ?? 3600) * 1000);
    await SettingsService.saveGoogleAccessToken(at, exp);
    return at;
  }

  Future<String?> _fetchEmail(String accessToken) async {
    try {
      final res = await http.get(
        Uri.parse(_userinfoEndpoint),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        return (d['email'] ?? d['name']) as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _storeTokens(_Tokens t) async {
    await SettingsService.saveGoogleAccessToken(t.accessToken, t.expiresAt);
    if (t.refreshToken != null) {
      await SettingsService.saveGoogleRefreshToken(t.refreshToken!);
    }
  }

  void _respondOk(HttpRequest req) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(
          '<html><body style="font-family:sans-serif;text-align:center;padding:40px">'
          '<h2>✓ Signed in</h2><p>You can close this tab.</p></body></html>')
      ..close();
  }

  // ── PKCE helpers ───────────────────────────────────────────────────────────

  String _codeVerifier() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _codeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _randomBase64(int bytes) {
    final b = List<int>.generate(bytes, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(b).replaceAll('=', '');
  }
}

class _Tokens {
  final String accessToken;
  final String? refreshToken;
  final int expiresAt;
  const _Tokens(
      {required this.accessToken, this.refreshToken, required this.expiresAt});
}
