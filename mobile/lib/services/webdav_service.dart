import 'dart:convert';
import 'dart:io' show HttpDate;
import 'package:http/http.dart' as http;
import '../models/workspace.dart';

class ConflictException implements Exception {
  const ConflictException();
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class RateLimitException implements Exception {
  final Duration retryAfter;
  const RateLimitException(this.retryAfter);
  @override
  String toString() => 'Server rate-limited — retry in ${retryAfter.inSeconds}s';
}

class WebDavService {
  final String fileUrl;
  final String username;
  final String password;

  const WebDavService({
    required this.fileUrl,
    required this.username,
    required this.password,
  });

  // Derives timer state URL by replacing .json → -timer.json,
  // mirroring the logic in WebDavSync.qml.
  String get timerUrl {
    if (fileUrl.endsWith('.json')) {
      return '${fileUrl.substring(0, fileUrl.length - 5)}-timer.json';
    }
    return '$fileUrl-timer.json';
  }

  Map<String, String> get _authHeaders {
    final creds = base64Encode(utf8.encode('$username:$password'));
    return {'Authorization': 'Basic $creds'};
  }

  // Returns (etag, workspaces).
  // workspaces is null when the file doesn't exist yet (HTTP 404).
  Future<(String, List<Workspace>?)> getWorkspaces() async {
    final response = await http
        .get(Uri.parse(fileUrl), headers: _authHeaders)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) return ('', null);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AuthException(
          'Authentication failed — check credentials in Settings');
    }
    if (response.statusCode == 429) {
      throw RateLimitException(_retryAfter(response.headers));
    }
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final etag = response.headers['etag'] ?? '';
    final data = jsonDecode(response.body) as List;
    final workspaces = data
        .map((w) => Workspace.fromJson(w as Map<String, dynamic>))
        .toList();
    return (etag, workspaces);
  }

  // Returns the new ETag.
  // Throws ConflictException on HTTP 412 Precondition Failed.
  Future<String> putWorkspaces(List<Workspace> workspaces, String etag) async {
    final headers = {
      ..._authHeaders,
      'Content-Type': 'application/json; charset=utf-8',
      if (etag.isNotEmpty) 'If-Match': etag,
    };
    final response = await http
        .put(
          Uri.parse(fileUrl),
          headers: headers,
          body: jsonEncode(workspaces.map((w) => w.toJson()).toList()),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 412) throw const ConflictException();
    if (response.statusCode == 429) {
      throw RateLimitException(_retryAfter(response.headers));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return response.headers['etag'] ?? '';
  }

  Future<void> putTimerState({
    required int sessionCount,
    required String timerMode,
    required bool isRunning,
    String? startTime,
    int totalDuration = 0,
    String? endTime,
    int remainingSeconds = 0,
    required String lastModified,
  }) async {
    final body = <String, dynamic>{
      'sessionCount': sessionCount,
      'timerMode': timerMode,
      'isRunning': isRunning,
      'remainingSeconds': remainingSeconds,
      'lastModified': lastModified,
    };
    if (isRunning && startTime != null) {
      body['startTime'] = startTime;
      body['totalDuration'] = totalDuration;
    }
    // endTime kept for backward compat with older clients
    if (endTime != null) body['endTime'] = endTime;

    await http
        .put(
          Uri.parse(timerUrl),
          headers: {
            ..._authHeaders,
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
  }

  // Read timer state. Returns server Date header, file Last-Modified header, and body.
  // Elapsed = serverDate - fileDate is purely server-clock-relative (no device clock skew).
  Future<({DateTime? serverDate, DateTime? fileDate, Map<String, dynamic>? data})>
      getTimerState() async {
    try {
      final response = await http
          .get(Uri.parse(timerUrl), headers: _authHeaders)
          .timeout(const Duration(seconds: 10));

      DateTime? serverDate;
      DateTime? fileDate;
      final ds = response.headers['date'];
      if (ds != null) {
        try { serverDate = HttpDate.parse(ds); } catch (_) {}
      }
      final lm = response.headers['last-modified'];
      if (lm != null) {
        try { fileDate = HttpDate.parse(lm); } catch (_) {}
      }

      if (response.statusCode == 200) {
        return (
          serverDate: serverDate,
          fileDate: fileDate,
          data: jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return (serverDate: null, fileDate: null, data: null);
  }

  static Duration _retryAfter(Map<String, String> headers) {
    final v = headers['retry-after'] ?? headers['Retry-After'];
    if (v != null) {
      final secs = int.tryParse(v);
      if (secs != null) return Duration(seconds: secs);
    }
    return const Duration(seconds: 60);
  }

  // HEAD request used by ConfigScreen to verify credentials and reachability.
  Future<(bool, String)> testConnection() async {
    try {
      final response = await http
          .head(Uri.parse(fileUrl), headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 404) {
        return (true, 'Connected');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return (false, 'Authentication failed — check username and password');
      } else {
        return (false, 'Server returned HTTP ${response.statusCode}');
      }
    } catch (e) {
      final msg = e.toString().contains('timeout')
          ? 'Connection timed out'
          : 'Network error — check the URL';
      return (false, msg);
    }
  }
}
