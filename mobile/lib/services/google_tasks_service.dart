// Google Tasks API v1 sync service.
// Ports the algorithm from GoogleTasksSync.qml exactly.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/workspace.dart';

class GoogleTasksService {
  static const _base = 'https://tasks.googleapis.com/tasks/v1';

  final String accessToken;
  GoogleTasksService(this.accessToken);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

  // ── Task lists ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listTaskLists() async {
    final res = await http.get(
      Uri.parse('$_base/users/@me/lists?maxResults=100'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('listTaskLists: ${res.statusCode}');
    final d = jsonDecode(res.body) as Map<String, dynamic>;
    return (d['items'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  // ── Tasks ──────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listTasks(String listId) async {
    final items = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final uri = Uri.parse('$_base/lists/$listId/tasks').replace(
        queryParameters: {
          'maxResults': '100',
          'showCompleted': 'true',
          'showHidden': 'true',
          'pageToken': pageToken,
        }..removeWhere((_, v) => v == null),
      );
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode != 200) throw Exception('listTasks: ${res.statusCode}');
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      items.addAll(
          (d['items'] as List? ?? []).map((e) => e as Map<String, dynamic>));
      pageToken = d['nextPageToken'] as String?;
    } while (pageToken != null);
    return items;
  }

  Future<String> createTask(String listId, Task task) async {
    final res = await http.post(
      Uri.parse('$_base/lists/$listId/tasks'),
      headers: _headers,
      body: jsonEncode(_taskToRemote(task)),
    );
    if (res.statusCode != 200) throw Exception('createTask: ${res.statusCode}');
    final d = jsonDecode(res.body) as Map<String, dynamic>;
    return d['id'] as String;
  }

  Future<void> updateTask(String listId, String taskId, Task task) async {
    final res = await http.patch(
      Uri.parse('$_base/lists/$listId/tasks/$taskId'),
      headers: _headers,
      body: jsonEncode(_taskToRemote(task)),
    );
    if (res.statusCode != 200) throw Exception('updateTask: ${res.statusCode}');
  }

  Future<void> deleteTask(String listId, String taskId) async {
    final res = await http.delete(
      Uri.parse('$_base/lists/$listId/tasks/$taskId'),
      headers: _headers,
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception('deleteTask: ${res.statusCode}');
    }
  }

  // ── Sync workspace ─────────────────────────────────────────────────────────

  // Returns updated workspace with googleTaskId + googleSyncedIds populated.
  Future<Workspace> syncWorkspace(Workspace ws) async {
    final listId = ws.googleTaskListId;
    if (listId.isEmpty) return ws;

    final remoteRaw = await listTasks(listId);
    final remoteById = <String, Map<String, dynamic>>{
      for (final r in remoteRaw) (r['id'] as String): r,
    };

    final prevSynced = ws.googleSyncedIds.toSet();
    final localByGid = <String, Task>{
      for (final t in ws.tasks)
        if (t.googleTaskId.isNotEmpty) t.googleTaskId: t,
    };

    final updatedTasks = <Task>[];
    final seen = <String>{};

    for (final task in ws.tasks) {
      final gid = task.googleTaskId;

      if (gid.isNotEmpty) {
        seen.add(gid);
        final remote = remoteById[gid];
        if (remote != null) {
          // Exists both sides — use newer lastModified.
          final remoteModified =
              remote['updated'] as String? ?? remote['due'] as String? ?? '';
          if (remoteModified.isNotEmpty &&
              remoteModified.compareTo(task.lastModified) > 0) {
            updatedTasks.add(_remoteToTask(remote, task));
          } else {
            // Local is newer — push update to remote.
            await updateTask(listId, gid, task);
            updatedTasks.add(task);
          }
        } else {
          // Only local, was previously synced → deleted remotely → drop.
          if (prevSynced.contains(gid)) {
            // skip — deleted on remote
          } else {
            // Never uploaded before — create on remote.
            final newGid = await createTask(listId, task);
            seen.add(newGid);
            updatedTasks.add(task.copyWith(googleTaskId: newGid));
          }
        }
      } else {
        // No google task ID yet — create on remote.
        final newGid = await createTask(listId, task);
        seen.add(newGid);
        updatedTasks.add(task.copyWith(googleTaskId: newGid));
      }
    }

    // Pull new remote tasks (not seen locally).
    for (final remote in remoteRaw) {
      final gid = remote['id'] as String;
      if (seen.contains(gid)) continue;
      if (prevSynced.contains(gid)) continue; // locally deleted — skip
      if (!localByGid.containsKey(gid)) {
        // New on remote — pull in.
        updatedTasks.add(_remoteToTask(remote, null));
        seen.add(gid);
      }
    }

    // Delete remote tasks that were locally deleted (in prevSynced, not seen).
    for (final gid in prevSynced) {
      if (!seen.contains(gid) && remoteById.containsKey(gid)) {
        await deleteTask(listId, gid);
      }
    }

    final newSyncedIds = updatedTasks
        .map((t) => t.googleTaskId)
        .where((id) => id.isNotEmpty)
        .toList();

    return ws.copyWith(
      tasks: updatedTasks,
      googleSyncedIds: newSyncedIds,
    );
  }

  // ── JSON helpers ───────────────────────────────────────────────────────────

  Map<String, dynamic> _taskToRemote(Task task) => {
        'title': task.title,
        'notes': task.description,
        'status': task.done ? 'completed' : 'needsAction',
      };

  Task _remoteToTask(Map<String, dynamic> r, Task? existing) {
    final gid = r['id'] as String;
    final done = (r['status'] as String?) == 'completed';
    final now = DateTime.now().toUtc().toIso8601String();
    return Task(
      uid: existing?.uid ?? gid,
      title: r['title'] as String? ?? '',
      description: r['notes'] as String? ?? '',
      done: done,
      lastModified: r['updated'] as String? ?? now,
      reminder: existing?.reminder ?? '',
      googleTaskId: gid,
    );
  }
}
