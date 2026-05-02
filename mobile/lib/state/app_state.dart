import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/workspace.dart';
import '../services/webdav_service.dart';
import '../services/settings_service.dart';
import '../services/google_auth_service.dart';
import '../services/google_tasks_service.dart';
import '../services/notification_service.dart';

enum SyncStatus { idle, syncing, ok, error }

class AppState extends ChangeNotifier {
  // ── Settings ───────────────────────────────────────────────────────────────
  String webdavUrl = '';
  String webdavUsername = '';
  bool webdavAutoSync = false;
  int webdavInterval = 5;
  int pomodoroMinutes = 25;
  int shortBreakMinutes = 5;
  int longBreakMinutes = 15;
  bool _hasPassword = false;
  bool get hasPassword => _hasPassword;

  // ── Google Tasks ───────────────────────────────────────────────────────────
  String googleClientId = '';
  String? googleEmail;
  bool googleAutoSync = false;
  SyncStatus googleSyncStatus = SyncStatus.idle;
  String googleSyncMessage = '';
  bool _googleSyncing = false;
  Timer? _googlePushDebounce;
  final _googleAuth = GoogleAuthService();

  // ── Workspaces / tasks ─────────────────────────────────────────────────────
  List<Workspace> workspaces = [];
  int _currentWorkspace = 0;
  int get currentWorkspace => _currentWorkspace;

  void switchWorkspace(int index) {
    if (index == _currentWorkspace || index >= workspaces.length) return;
    _currentWorkspace = index;
    notifyListeners();
  }

  // ── Timer ──────────────────────────────────────────────────────────────────
  int remainingSeconds = 25 * 60;
  bool isRunning = false;
  bool isPaused = false;
  String timerMode = 'work'; // 'work' | 'shortBreak' | 'longBreak'
  int sessionCount = 0;

  // ── Sync ───────────────────────────────────────────────────────────────────
  SyncStatus syncStatus = SyncStatus.idle;
  String syncMessage = '';
  bool _pendingTimerPush = false;
  int _pendingSessionCount = 0;
  String _pendingTimerMode = '';
  String _timerLastModified = '';

  // ── Internals ──────────────────────────────────────────────────────────────
  Timer? _pomodoroTimer;
  Timer? _pushDebounce;
  Timer? _periodicSync;
  Timer? _fastPollTimer;
  bool _syncing = false;
  WebDavService? _webdav;
  final _uuid = const Uuid();
  DateTime? _timerEndTime;

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> init() async {
    webdavUrl = await SettingsService.getUrl();
    webdavUsername = await SettingsService.getUsername();
    webdavAutoSync = await SettingsService.getAutoSync();
    webdavInterval = await SettingsService.getInterval();
    pomodoroMinutes = await SettingsService.getPomodoroMinutes();
    shortBreakMinutes = await SettingsService.getShortBreakMinutes();
    longBreakMinutes = await SettingsService.getLongBreakMinutes();
    remainingSeconds = pomodoroMinutes * 60;

    final password = await SettingsService.getPassword();
    _hasPassword = password != null && password.isNotEmpty;
    if (_hasPassword) {
      _webdav = WebDavService(
        fileUrl: webdavUrl,
        username: webdavUsername,
        password: password!,
      );
    }

    if (webdavUrl.isNotEmpty && _hasPassword) {
      await sync();
      if (webdavAutoSync) _startPeriodicSync();
    }

    googleClientId = await SettingsService.getGoogleClientId();
    googleEmail = await SettingsService.getGoogleEmail();
    googleAutoSync = await SettingsService.getGoogleAutoSync();

    if (workspaces.isEmpty) {
      workspaces = [const Workspace(name: 'Default')];
    }

    if (googleAutoSync && googleClientId.isNotEmpty) {
      final connected = await _googleAuth.isConnected;
      if (connected) syncGoogle();
    }

    notifyListeners();
  }

  void _startPeriodicSync() {
    _periodicSync?.cancel();
    if (webdavInterval <= 0) return;
    _periodicSync =
        Timer.periodic(Duration(minutes: webdavInterval), (_) {
      if (!_syncing) sync();
    });
  }

  // ── Sync ───────────────────────────────────────────────────────────────────
  Future<void> sync() async {
    if (_syncing || _webdav == null) return;
    _syncing = true;
    syncStatus = SyncStatus.syncing;
    syncMessage = 'Syncing…';
    notifyListeners();

    try {
      var (etag, remote) = await _webdav!.getWorkspaces();

      List<Workspace> merged;
      if (remote == null || remote.isEmpty) {
        // File doesn't exist yet — use local data as initial content.
        merged = workspaces.isEmpty
            ? [const Workspace(name: 'Default')]
            : List.from(workspaces);
      } else {
        merged = workspaces.isEmpty ? remote : _merge(workspaces, remote);
      }

      // Stamp webdavSyncedUids for next-sync deletion detection.
      merged = merged
          .map((ws) => ws.copyWith(
                webdavSyncedUids: ws.tasks
                    .map((t) => t.uid)
                    .where((u) => u.isNotEmpty)
                    .toList(),
              ))
          .toList();

      try {
        await _webdav!.putWorkspaces(merged, etag);
      } on ConflictException {
        // Another client wrote the file while we were merging — retry once.
        final (etag2, remote2) = await _webdav!.getWorkspaces();
        final merged2 = remote2 == null || remote2.isEmpty
            ? merged
            : _merge(workspaces, remote2);
        final stamped2 = merged2
            .map((ws) => ws.copyWith(
                  webdavSyncedUids: ws.tasks
                      .map((t) => t.uid)
                      .where((u) => u.isNotEmpty)
                      .toList(),
                ))
            .toList();
        await _webdav!.putWorkspaces(stamped2, etag2);
        merged = stamped2;
      }

      workspaces = merged;
      if (_currentWorkspace >= workspaces.length) _currentWorkspace = 0;
      syncStatus = SyncStatus.ok;
      syncMessage = 'Synced';

      if (_pendingTimerPush) _doPushTimerState();
      _pollTimerState().ignore();
    } catch (e) {
      syncStatus = SyncStatus.error;
      syncMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  void schedulePush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 2), () {
      if (!_syncing) sync();
    });
  }

  // ── Merge — mirrors WebDavSync.qml _merge() / _mergeTasks() exactly ───────
  List<Workspace> _merge(List<Workspace> local, List<Workspace> remote) {
    final remoteByName = {for (final w in remote) w.name: w};
    final localNames = {for (final w in local) w.name};
    final result = <Workspace>[];

    for (final localWs in local) {
      final remoteWs = remoteByName[localWs.name];
      if (remoteWs == null) {
        result.add(localWs);
        continue;
      }
      result.add(localWs.copyWith(tasks: _mergeTasks(localWs, remoteWs)));
    }

    for (final remoteWs in remote) {
      if (!localNames.contains(remoteWs.name)) result.add(remoteWs);
    }

    return result;
  }

  List<Task> _mergeTasks(Workspace localWs, Workspace remoteWs) {
    final localByUid = {
      for (final t in localWs.tasks)
        if (t.uid.isNotEmpty) t.uid: t
    };
    final remoteByUid = {
      for (final t in remoteWs.tasks)
        if (t.uid.isNotEmpty) t.uid: t
    };
    final prevSynced = localWs.webdavSyncedUids.toSet();
    final allUids = {...localByUid.keys, ...remoteByUid.keys};
    final seen = <String>{};
    final result = <Task>[];

    for (final uid in allUids) {
      if (!seen.add(uid)) continue;
      final loc = localByUid[uid];
      final rem = remoteByUid[uid];

      if (loc != null && rem != null) {
        result.add(rem.lastModified.compareTo(loc.lastModified) > 0 ? rem : loc);
      } else if (loc != null) {
        // Only local: not in prevSynced → added locally → keep.
        if (!prevSynced.contains(uid)) result.add(loc);
      } else if (rem != null) {
        // Only remote: not in prevSynced → added remotely → pull.
        if (!prevSynced.contains(uid)) result.add(rem);
      }
    }

    // Tasks without uid — preserve all to avoid data loss.
    for (final t in localWs.tasks) {
      if (t.uid.isEmpty) result.add(t);
    }
    for (final t in remoteWs.tasks) {
      if (t.uid.isEmpty) result.add(t);
    }

    return result;
  }

  // ── Task mutations ─────────────────────────────────────────────────────────
  String get _now => DateTime.now().toUtc().toIso8601String();

  void addTask(String title, {bool urgent = false, bool important = false}) {
    if (title.trim().isEmpty || workspaces.isEmpty) return;
    final task = Task(
      uid: _uuid.v4(),
      title: title.trim(),
      lastModified: _now,
      urgent: urgent,
      important: important,
    );
    final ws = workspaces[_currentWorkspace];
    workspaces = List.from(workspaces)
      ..[_currentWorkspace] = ws.copyWith(tasks: [...ws.tasks, task]);
    notifyListeners();
    schedulePush();
  }

  void toggleTask(int wsIndex, int taskIndex) {
    final ws = workspaces[wsIndex];
    final task = ws.tasks[taskIndex];
    final newTasks = List<Task>.from(ws.tasks)
      ..[taskIndex] = task.copyWith(done: !task.done, lastModified: _now);
    workspaces = List.from(workspaces)
      ..[wsIndex] = ws.copyWith(tasks: newTasks);
    notifyListeners();
    schedulePush();
  }

  void deleteTask(int wsIndex, int taskIndex) {
    final ws = workspaces[wsIndex];
    final newTasks = List<Task>.from(ws.tasks)..removeAt(taskIndex);
    workspaces = List.from(workspaces)
      ..[wsIndex] = ws.copyWith(tasks: newTasks);
    notifyListeners();
    schedulePush();
  }

  void updateTaskTitle(int wsIndex, int taskIndex, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final ws = workspaces[wsIndex];
    final task = ws.tasks[taskIndex];
    if (task.title == trimmed) return;
    final newTasks = List<Task>.from(ws.tasks)
      ..[taskIndex] = task.copyWith(title: trimmed, lastModified: _now);
    workspaces = List.from(workspaces)
      ..[wsIndex] = ws.copyWith(tasks: newTasks);
    notifyListeners();
    schedulePush();
  }

  void setTaskPriority(int wsIndex, int taskIndex,
      {required bool urgent, required bool important}) {
    final ws = workspaces[wsIndex];
    final task = ws.tasks[taskIndex];
    if (task.urgent == urgent && task.important == important) return;
    final newTasks = List<Task>.from(ws.tasks)
      ..[taskIndex] = task.copyWith(
          urgent: urgent, important: important, lastModified: _now);
    workspaces = List.from(workspaces)
      ..[wsIndex] = ws.copyWith(tasks: newTasks);
    notifyListeners();
    schedulePush();
  }

  // ── Timer ──────────────────────────────────────────────────────────────────
  int get timerDuration {
    if (timerMode == 'work') return pomodoroMinutes * 60;
    if (timerMode == 'shortBreak') return shortBreakMinutes * 60;
    return longBreakMinutes * 60;
  }

  String get timerLabel {
    if (timerMode == 'work') return 'Focus';
    if (timerMode == 'shortBreak') return 'Short Break';
    return 'Long Break';
  }

  String get formattedTime {
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void startTimer() {
    if (isRunning) return;
    isRunning = true;
    isPaused = false;
    _timerEndTime = DateTime.now().add(Duration(seconds: remainingSeconds));
    _timerLastModified = DateTime.now().toUtc().toIso8601String();
    _startFastPoll();
    _pushLiveTimerState();
    NotificationService.showRunning(_timerEndTime!, timerLabel);
    NotificationService.scheduleComplete(_timerEndTime!, timerLabel);
    _pomodoroTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  void pauseTimer() {
    _pomodoroTimer?.cancel();
    isRunning = false;
    isPaused = true;
    _timerEndTime = null;
    _timerLastModified = DateTime.now().toUtc().toIso8601String();
    _stopFastPoll();
    _pushLiveTimerState();
    NotificationService.cancelAll();
    notifyListeners();
  }

  void resetTimer() {
    _pomodoroTimer?.cancel();
    isRunning = false;
    isPaused = false;
    _timerEndTime = null;
    remainingSeconds = timerDuration;
    _timerLastModified = DateTime.now().toUtc().toIso8601String();
    _stopFastPoll();
    _pushLiveTimerState();
    NotificationService.cancelAll();
    notifyListeners();
  }

  // Called on app resume — recalculates remaining time from stored end time,
  // then also polls the server in case a remote device changed the timer.
  void syncFromBackground() {
    if (_timerEndTime != null && isRunning) {
      final remaining = _timerEndTime!.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        _pomodoroTimer?.cancel();
        isRunning = false;
        isPaused = false;
        _advanceMode();
        _timerEndTime = null;
        _stopFastPoll();
        NotificationService.cancelRunning();
        pushTimerState(sessionCount, timerMode);
      } else {
        remainingSeconds = remaining;
      }
      notifyListeners();
    }
    // Always poll remote timer state on resume.
    _pollTimerState();
  }

  void _startFastPoll() {
    _fastPollTimer?.cancel();
    if (_webdav == null) return;
    _fastPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _pollTimerState();
    });
  }

  void _stopFastPoll() {
    _fastPollTimer?.cancel();
    _fastPollTimer = null;
  }

  Future<void> _pollTimerState() async {
    if (_webdav == null) return;
    try {
      final data = await _webdav!.getTimerState();
      if (data != null) _applyRemoteTimer(data);
    } catch (_) {}
  }

  void _applyRemoteTimer(Map<String, dynamic> data) {
    final remoteModStr = data['lastModified'] as String?;
    if (remoteModStr == null) return;
    // Ignore if remote is not newer than our last local change.
    if (_timerLastModified.isNotEmpty &&
        remoteModStr.compareTo(_timerLastModified) <= 0) {
      return;
    }

    final remoteRunning = data['isRunning'] as bool? ?? false;
    final remoteEndTimeStr = data['endTime'] as String?;
    final remoteMode = data['timerMode'] as String? ?? 'work';
    final remoteCount = data['sessionCount'] as int? ?? 0;
    final remoteRemaining = data['remainingSeconds'] as int? ?? 0;

    _timerLastModified = remoteModStr;

    if (remoteRunning && remoteEndTimeStr != null) {
      final endTime = DateTime.tryParse(remoteEndTimeStr);
      if (endTime == null) return;
      final remaining = endTime.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) return;

      timerMode = remoteMode;
      sessionCount = remoteCount;
      remainingSeconds = remaining;
      _timerEndTime = endTime;

      if (!isRunning) {
        isRunning = true;
        isPaused = false;
        _pomodoroTimer?.cancel();
        _pomodoroTimer =
            Timer.periodic(const Duration(seconds: 1), (_) => _tick());
        _startFastPoll();
        NotificationService.showRunning(endTime, timerLabel);
        NotificationService.scheduleComplete(endTime, timerLabel);
      }
      // If already running: remainingSeconds is updated above; existing tick continues.
    } else {
      if (isRunning) {
        _pomodoroTimer?.cancel();
        isRunning = false;
        _timerEndTime = null;
        _stopFastPoll();
        NotificationService.cancelAll();
      }
      timerMode = remoteMode;
      sessionCount = remoteCount;
      final dur = timerDuration;
      remainingSeconds =
          (remoteRemaining > 0 && remoteRemaining < dur) ? remoteRemaining : dur;
      isPaused = remainingSeconds < dur;
    }

    notifyListeners();
  }

  void skipMode() {
    _pomodoroTimer?.cancel();
    isRunning = false;
    isPaused = false;
    _timerEndTime = null;
    _timerLastModified = DateTime.now().toUtc().toIso8601String();
    _stopFastPoll();
    NotificationService.cancelAll();
    _advanceMode();
    _pushLiveTimerState();
    notifyListeners();
  }

  void _tick() {
    if (remainingSeconds > 0) {
      remainingSeconds--;
      notifyListeners();
    } else {
      _pomodoroTimer?.cancel();
      isRunning = false;
      isPaused = false;
      final completedLabel = timerLabel;
      _advanceMode();
      _timerEndTime = null;
      _stopFastPoll();
      NotificationService.cancelAll();
      NotificationService.showComplete(completedLabel);
      pushTimerState(sessionCount, timerMode); // retried until WebDAV confirms
      notifyListeners();
    }
  }

  void _advanceMode() {
    if (timerMode == 'work') {
      sessionCount++;
      timerMode = (sessionCount % 4 == 0) ? 'longBreak' : 'shortBreak';
    } else {
      timerMode = 'work';
    }
    remainingSeconds = timerDuration;
  }

  // ── Timer state sync ───────────────────────────────────────────────────────
  void pushTimerState(int count, String mode) {
    if (_webdav == null) return;
    _pendingTimerPush = true;
    _pendingSessionCount = count;
    _pendingTimerMode = mode;
    _timerLastModified = DateTime.now().toUtc().toIso8601String();
    _doPushTimerState();
  }

  Future<void> _doPushTimerState() async {
    if (_webdav == null) return;
    try {
      await _webdav!.putTimerState(
        sessionCount: _pendingSessionCount,
        timerMode: _pendingTimerMode,
        isRunning: false,
        remainingSeconds: timerDuration,
        lastModified: _timerLastModified,
      );
      _pendingTimerPush = false;
    } catch (_) {
      // Retried on next successful task sync.
    }
  }

  // Fire-and-forget — used for start/pause/reset/skip (live state changes).
  void _pushLiveTimerState() {
    if (_webdav == null) return;
    final endTime = _timerEndTime?.toUtc().toIso8601String();
    final mod = _timerLastModified;
    final count = sessionCount;
    final mode = timerMode;
    final running = isRunning;
    final remaining = remainingSeconds;
    _webdav!
        .putTimerState(
          sessionCount: count,
          timerMode: mode,
          isRunning: running,
          endTime: endTime,
          remainingSeconds: remaining,
          lastModified: mod,
        )
        .ignore();
  }

  // ── Google Tasks sync ──────────────────────────────────────────────────────

  Future<String?> signInGoogle() async {
    if (googleClientId.isEmpty) return 'Enter a Client ID first.';
    final email = await _googleAuth.authorize(googleClientId);
    if (email == null) return 'Sign-in cancelled or failed.';
    googleEmail = email;
    await SettingsService.saveGoogleEmail(email);
    notifyListeners();
    return null;
  }

  Future<void> signOutGoogle() async {
    await _googleAuth.signOut();
    googleEmail = null;
    googleSyncStatus = SyncStatus.idle;
    googleSyncMessage = '';
    notifyListeners();
  }

  Future<String?> getGoogleAccessToken() =>
      _googleAuth.getAccessToken(googleClientId);

  Future<List<Map<String, dynamic>>> listGoogleTaskLists() async {
    final token = await getGoogleAccessToken();
    if (token == null) return [];
    return GoogleTasksService(token).listTaskLists();
  }

  void setWorkspaceGoogleList(int wsIndex, String listId) {
    final ws = workspaces[wsIndex];
    workspaces = List.from(workspaces)
      ..[wsIndex] = ws.copyWith(googleTaskListId: listId, googleSyncedIds: []);
    notifyListeners();
    if (googleAutoSync) _scheduleGooglePush();
  }

  void _scheduleGooglePush() {
    _googlePushDebounce?.cancel();
    _googlePushDebounce = Timer(const Duration(seconds: 2), () {
      if (!_googleSyncing) syncGoogle();
    });
  }

  Future<void> syncGoogle() async {
    if (_googleSyncing || googleClientId.isEmpty) return;
    final token = await _googleAuth.getAccessToken(googleClientId);
    if (token == null) {
      googleSyncStatus = SyncStatus.error;
      googleSyncMessage = 'Not signed in';
      notifyListeners();
      return;
    }

    _googleSyncing = true;
    googleSyncStatus = SyncStatus.syncing;
    googleSyncMessage = 'Syncing…';
    notifyListeners();

    try {
      final svc = GoogleTasksService(token);
      final updated = List<Workspace>.from(workspaces);
      for (int i = 0; i < updated.length; i++) {
        if (updated[i].googleTaskListId.isNotEmpty) {
          updated[i] = await svc.syncWorkspace(updated[i]);
        }
      }
      workspaces = updated;
      googleSyncStatus = SyncStatus.ok;
      googleSyncMessage = 'Synced';
    } catch (e) {
      googleSyncStatus = SyncStatus.error;
      googleSyncMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _googleSyncing = false;
      notifyListeners();
    }
  }

  Future<void> saveGoogleSettings({
    required String clientId,
    required bool autoSync,
  }) async {
    googleClientId = clientId;
    googleAutoSync = autoSync;
    await Future.wait([
      SettingsService.saveGoogleClientId(clientId),
      SettingsService.saveGoogleAutoSync(autoSync),
    ]);
    notifyListeners();
  }

  // ── Settings save ──────────────────────────────────────────────────────────
  Future<void> saveSettings({
    required String url,
    required String username,
    String? password,
    required bool autoSync,
    required int interval,
    required int pomodoroMin,
    required int shortBreakMin,
    required int longBreakMin,
  }) async {
    webdavUrl = url;
    webdavUsername = username;
    webdavAutoSync = autoSync;
    webdavInterval = interval;
    pomodoroMinutes = pomodoroMin;
    shortBreakMinutes = shortBreakMin;
    longBreakMinutes = longBreakMin;

    await Future.wait([
      SettingsService.saveUrl(url),
      SettingsService.saveUsername(username),
      SettingsService.saveAutoSync(autoSync),
      SettingsService.saveInterval(interval),
      SettingsService.savePomodoroMinutes(pomodoroMin),
      SettingsService.saveShortBreakMinutes(shortBreakMin),
      SettingsService.saveLongBreakMinutes(longBreakMin),
    ]);

    if (password != null && password.isNotEmpty) {
      await SettingsService.savePassword(password);
      _hasPassword = true;
    }

    final pw = await SettingsService.getPassword();
    if (url.isNotEmpty && pw != null && pw.isNotEmpty) {
      _webdav =
          WebDavService(fileUrl: url, username: username, password: pw);
    }

    _periodicSync?.cancel();
    if (autoSync && url.isNotEmpty && _hasPassword) _startPeriodicSync();

    notifyListeners();
  }

  @override
  void dispose() {
    _pomodoroTimer?.cancel();
    _pushDebounce?.cancel();
    _periodicSync?.cancel();
    _fastPollTimer?.cancel();
    _googlePushDebounce?.cancel();
    super.dispose();
  }
}
