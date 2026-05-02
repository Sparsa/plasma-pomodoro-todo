import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Thin wrapper so screens never touch storage keys directly.
class SettingsService {
  static const _store = FlutterSecureStorage();
  static const _kPassword = 'webdav_password';
  static const _kGoogleAccessToken = 'google_access_token';
  static const _kGoogleRefreshToken = 'google_refresh_token';

  // ── Secure storage (passwords / tokens) ───────────────────────────────────
  static Future<String?> getPassword() => _store.read(key: _kPassword);
  static Future<void> savePassword(String p) =>
      _store.write(key: _kPassword, value: p);
  static Future<void> clearPassword() => _store.delete(key: _kPassword);

  static Future<String?> getGoogleAccessToken() =>
      _store.read(key: _kGoogleAccessToken);
  static Future<String?> getGoogleRefreshToken() =>
      _store.read(key: _kGoogleRefreshToken);

  static Future<void> saveGoogleAccessToken(String token, int expiresAt) async {
    await _store.write(key: _kGoogleAccessToken, value: token);
    (await _p).setInt('googleTokenExpiry', expiresAt);
  }

  static Future<void> saveGoogleRefreshToken(String token) =>
      _store.write(key: _kGoogleRefreshToken, value: token);

  static Future<void> clearGoogleTokens() async {
    await Future.wait([
      _store.delete(key: _kGoogleAccessToken),
      _store.delete(key: _kGoogleRefreshToken),
    ]);
    (await _p).remove('googleTokenExpiry');
    (await _p).remove('googleClientId');
    (await _p).remove('googleEmail');
  }

  // ── Shared preferences (non-sensitive config) ──────────────────────────────
  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  static Future<int> getGoogleTokenExpiry() async =>
      (await _p).getInt('googleTokenExpiry') ?? 0;
  static Future<String> getGoogleClientId() async =>
      (await _p).getString('googleClientId') ?? '';
  static Future<String?> getGoogleEmail() async =>
      (await _p).getString('googleEmail');
  static Future<bool> getGoogleAutoSync() async =>
      (await _p).getBool('googleAutoSync') ?? false;

  static Future<void> saveGoogleClientId(String v) async =>
      (await _p).setString('googleClientId', v);
  static Future<void> saveGoogleEmail(String v) async =>
      (await _p).setString('googleEmail', v);
  static Future<void> saveGoogleAutoSync(bool v) async =>
      (await _p).setBool('googleAutoSync', v);

  static Future<String> getUrl() async =>
      (await _p).getString('webdavUrl') ?? '';
  static Future<String> getUsername() async =>
      (await _p).getString('webdavUsername') ?? '';
  static Future<bool> getAutoSync() async =>
      (await _p).getBool('webdavAutoSync') ?? false;
  static Future<int> getInterval() async =>
      (await _p).getInt('webdavInterval') ?? 5;
  static Future<int> getPomodoroMinutes() async =>
      (await _p).getInt('pomodoroMinutes') ?? 25;
  static Future<int> getShortBreakMinutes() async =>
      (await _p).getInt('shortBreakMinutes') ?? 5;
  static Future<int> getLongBreakMinutes() async =>
      (await _p).getInt('longBreakMinutes') ?? 15;

  static Future<void> saveUrl(String v) async =>
      (await _p).setString('webdavUrl', v);
  static Future<void> saveUsername(String v) async =>
      (await _p).setString('webdavUsername', v);
  static Future<void> saveAutoSync(bool v) async =>
      (await _p).setBool('webdavAutoSync', v);
  static Future<void> saveInterval(int v) async =>
      (await _p).setInt('webdavInterval', v);
  static Future<void> savePomodoroMinutes(int v) async =>
      (await _p).setInt('pomodoroMinutes', v);
  static Future<void> saveShortBreakMinutes(int v) async =>
      (await _p).setInt('shortBreakMinutes', v);
  static Future<void> saveLongBreakMinutes(int v) async =>
      (await _p).setInt('longBreakMinutes', v);
}
