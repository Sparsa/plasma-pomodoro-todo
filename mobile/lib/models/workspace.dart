// Data models — schema must stay in sync with the QML plasmoid's JSON format.
// Fields like googleTaskListId / googleSyncedIds are preserved on round-trip
// so the desktop plasmoid never loses its Google Tasks linkage.

class Task {
  final String uid;
  final String title;
  final String description;
  final bool done;
  final String lastModified;
  final String reminder;
  final String googleTaskId;
  final bool urgent;
  final bool important;
  final int pomodorosCompleted;

  const Task({
    required this.uid,
    required this.title,
    this.description = '',
    this.done = false,
    required this.lastModified,
    this.reminder = '',
    this.googleTaskId = '',
    this.urgent = false,
    this.important = false,
    this.pomodorosCompleted = 0,
  });

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        uid: j['uid'] as String? ?? '',
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        done: j['done'] as bool? ?? false,
        lastModified: j['lastModified'] as String? ?? '',
        reminder: j['reminder'] as String? ?? '',
        googleTaskId: j['googleTaskId'] as String? ?? '',
        urgent: j['urgent'] as bool? ?? false,
        important: j['important'] as bool? ?? false,
        pomodorosCompleted: j['pomodorosCompleted'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'title': title,
        'description': description,
        'done': done,
        'lastModified': lastModified,
        'reminder': reminder,
        'googleTaskId': googleTaskId,
        'urgent': urgent,
        'important': important,
        'pomodorosCompleted': pomodorosCompleted,
      };

  // Q1 = urgent+important (Do First), Q2 = important (!urgent), Q3 = urgent (!important), Q4 = neither
  int get quadrant {
    if (urgent && important) return 1;
    if (!urgent && important) return 2;
    if (urgent && !important) return 3;
    return 4;
  }

  Task copyWith({
    String? uid,
    String? title,
    String? description,
    bool? done,
    String? lastModified,
    String? reminder,
    String? googleTaskId,
    bool? urgent,
    bool? important,
    int? pomodorosCompleted,
  }) =>
      Task(
        uid: uid ?? this.uid,
        title: title ?? this.title,
        description: description ?? this.description,
        done: done ?? this.done,
        lastModified: lastModified ?? this.lastModified,
        reminder: reminder ?? this.reminder,
        googleTaskId: googleTaskId ?? this.googleTaskId,
        urgent: urgent ?? this.urgent,
        important: important ?? this.important,
        pomodorosCompleted: pomodorosCompleted ?? this.pomodorosCompleted,
      );
}

class Workspace {
  final String name;
  final List<Task> tasks;
  final List<String> webdavSyncedUids;
  final String googleTaskListId;
  final List<String> googleSyncedIds;

  const Workspace({
    required this.name,
    this.tasks = const [],
    this.webdavSyncedUids = const [],
    this.googleTaskListId = '',
    this.googleSyncedIds = const [],
  });

  factory Workspace.fromJson(Map<String, dynamic> j) => Workspace(
        name: j['name'] as String? ?? '',
        tasks: (j['tasks'] as List? ?? [])
            .map((t) => Task.fromJson(t as Map<String, dynamic>))
            .toList(),
        webdavSyncedUids: (j['webdavSyncedUids'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
        googleTaskListId: j['googleTaskListId'] as String? ?? '',
        googleSyncedIds: (j['googleSyncedIds'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'webdavSyncedUids': webdavSyncedUids,
        'googleTaskListId': googleTaskListId,
        'googleSyncedIds': googleSyncedIds,
      };

  Workspace copyWith({
    String? name,
    List<Task>? tasks,
    List<String>? webdavSyncedUids,
    String? googleTaskListId,
    List<String>? googleSyncedIds,
  }) =>
      Workspace(
        name: name ?? this.name,
        tasks: tasks ?? this.tasks,
        webdavSyncedUids: webdavSyncedUids ?? this.webdavSyncedUids,
        googleTaskListId: googleTaskListId ?? this.googleTaskListId,
        googleSyncedIds: googleSyncedIds ?? this.googleSyncedIds,
      );
}
