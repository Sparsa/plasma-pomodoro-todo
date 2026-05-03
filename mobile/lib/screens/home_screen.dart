import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/workspace.dart';
import 'settings_screen.dart';

enum _ViewMode { list, matrix }

const _q1Color = Color(0xFFe74c3c); // urgent + important  → Do First
const _q2Color = Color(0xFF3498db); // important, not urgent → Schedule
const _q3Color = Color(0xFFf39c12); // urgent, not important → Delegate
const _q4Color = Color(0xFF95a5a6); // neither              → Eliminate

Color _quadrantColor(bool urgent, bool important) {
  if (urgent && important) return _q1Color;
  if (!urgent && important) return _q2Color;
  if (urgent && !important) return _q3Color;
  return _q4Color;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _addCtrl = TextEditingController();
  _ViewMode _viewMode = _ViewMode.list;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _addCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final s = context.read<AppState>();
      s.syncFromBackground();
      s.sync();
    }
  }

  void _showAddTask(AppState state) {
    _addCtrl.clear();
    var urgent = false;
    var important = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _addCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: 'New task…',
                      border: OutlineInputBorder()),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      state.addTask(v,
                          urgent: urgent, important: important);
                      Navigator.pop(ctx);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  if (_addCtrl.text.trim().isNotEmpty) {
                    state.addTask(_addCtrl.text,
                        urgent: urgent, important: important);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Add'),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              FilterChip(
                label: const Text('Urgent'),
                selected: urgent,
                selectedColor: _q1Color.withValues(alpha: 0.25),
                checkmarkColor: _q1Color,
                onSelected: (v) => setSheetState(() => urgent = v),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Important'),
                selected: important,
                selectedColor: _q2Color.withValues(alpha: 0.25),
                checkmarkColor: _q2Color,
                onSelected: (v) => setSheetState(() => important = v),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ws = state.workspaces.isEmpty
        ? null
        : state.workspaces[state.currentWorkspace];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomodoro Todo'),
        actions: [
          if (state.webdavUrl.isNotEmpty) _SyncButton(state: state),
          if (state.googleEmail != null) _GoogleSyncButton(state: state),
          IconButton(
            icon: Icon(_viewMode == _ViewMode.matrix
                ? Icons.list
                : Icons.grid_view_rounded),
            tooltip: _viewMode == _ViewMode.matrix
                ? 'List view'
                : 'Matrix view',
            onPressed: () => setState(() => _viewMode =
                _viewMode == _ViewMode.matrix
                    ? _ViewMode.list
                    : _ViewMode.matrix),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.syncStatus == SyncStatus.error)
            _SyncErrorBanner(message: state.syncMessage, onRetry: state.sync),
          _TimerCard(state: state),
          if (state.workspaces.length > 1) _WorkspaceTabs(state: state),
          Expanded(
            child: _viewMode == _ViewMode.matrix
                ? _MatrixView(
                    state: state,
                    wsIndex: state.currentWorkspace,
                  )
                : (ws == null || ws.tasks.isEmpty
                    ? Center(
                        child: Text(
                          'No tasks yet.\nTap + to add one.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: ws.tasks.length,
                        itemBuilder: (ctx, i) => _TaskTile(
                          task: ws.tasks[i],
                          onToggle: () => state.toggleTask(
                              state.currentWorkspace, i),
                          onDelete: () => state.deleteTask(
                              state.currentWorkspace, i),
                          onUpdate: (title, urgent, important) {
                            state.updateTaskTitle(
                                state.currentWorkspace, i, title);
                            state.setTaskPriority(state.currentWorkspace,
                                i,
                                urgent: urgent,
                                important: important);
                          },
                        ),
                      )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTask(state),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Sync buttons ──────────────────────────────────────────────────────────────
class _SyncButton extends StatelessWidget {
  final AppState state;
  const _SyncButton({required this.state});

  @override
  Widget build(BuildContext context) {
    final Widget icon = switch (state.syncStatus) {
      SyncStatus.syncing => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
        ),
      SyncStatus.error =>
        const Icon(Icons.cloud_off_outlined, color: Colors.redAccent),
      SyncStatus.ok => const Icon(Icons.cloud_done_outlined),
      _ => const Icon(Icons.sync),
    };
    return Tooltip(
      message: state.syncMessage.isNotEmpty
          ? state.syncMessage
          : 'Sync with WebDAV',
      child: IconButton(icon: icon, onPressed: state.sync),
    );
  }
}

class _GoogleSyncButton extends StatelessWidget {
  final AppState state;
  const _GoogleSyncButton({required this.state});

  @override
  Widget build(BuildContext context) {
    final Widget icon = switch (state.googleSyncStatus) {
      SyncStatus.syncing => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
        ),
      SyncStatus.error =>
        const Icon(Icons.cloud_off_outlined, color: Colors.orangeAccent),
      SyncStatus.ok => const Icon(Icons.task_alt_outlined),
      _ => const Icon(Icons.checklist),
    };
    return Tooltip(
      message: state.googleSyncMessage.isNotEmpty
          ? state.googleSyncMessage
          : 'Sync with Google Tasks',
      child: IconButton(icon: icon, onPressed: state.syncGoogle),
    );
  }
}

// ── Sync error banner ─────────────────────────────────────────────────────────
class _SyncErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _SyncErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            const Icon(Icons.cloud_off_outlined,
                size: 16, color: Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message.isNotEmpty ? message : 'WebDAV sync failed',
                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      );
}

// ── Timer card ────────────────────────────────────────────────────────────────
class _TimerCard extends StatelessWidget {
  final AppState state;
  const _TimerCard({required this.state});

  Color get _modeColor => state.timerMode == 'work'
      ? const Color(0xFFe74c3c)
      : const Color(0xFF27ae60);

  @override
  Widget build(BuildContext context) {
    final total = state.timerDuration;
    final elapsed = total - state.remainingSeconds;
    final progress = total > 0 ? elapsed / total : 0.0;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(children: [
          Text(
            state.timerLabel,
            style: TextStyle(
                fontSize: 13,
                color: _modeColor,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(_modeColor),
              ),
            ),
            Text(
              state.formattedTime,
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2),
            ),
          ]),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              icon: const Icon(Icons.stop_rounded),
              tooltip: 'Reset',
              onPressed: state.resetTimer,
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: _modeColor),
              icon: Icon(state.isRunning
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
              label: Text(state.isRunning ? 'Pause' : 'Start'),
              onPressed:
                  state.isRunning ? state.pauseTimer : state.startTimer,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded),
              tooltip: 'Skip',
              onPressed: state.skipMode,
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            'Sessions today: ${state.sessionCount}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ]),
      ),
    );
  }
}

// ── Workspace tab strip ───────────────────────────────────────────────────────
class _WorkspaceTabs extends StatelessWidget {
  final AppState state;
  const _WorkspaceTabs({required this.state});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: state.workspaces.length,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(state.workspaces[i].name),
            selected: i == state.currentWorkspace,
            onSelected: (_) =>
                context.read<AppState>().switchWorkspace(i),
          ),
        ),
      ),
    );
  }
}

// ── Task tile (list view) ─────────────────────────────────────────────────────
class _TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final void Function(String title, bool urgent, bool important) onUpdate;

  const _TaskTile({
    required this.task,
    required this.onToggle,
    required this.onDelete,
    required this.onUpdate,
  });

  void _showEditDialog(BuildContext context) {
    final ctrl = TextEditingController(text: task.title);
    var urgent = task.urgent;
    var important = task.important;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Edit task'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              onSubmitted: (v) {
                onUpdate(v, urgent, important);
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 12),
            Row(children: [
              FilterChip(
                label: const Text('Urgent'),
                selected: urgent,
                selectedColor: _q1Color.withValues(alpha: 0.25),
                checkmarkColor: _q1Color,
                onSelected: (v) => setDlgState(() => urgent = v),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Important'),
                selected: important,
                selectedColor: _q2Color.withValues(alpha: 0.25),
                checkmarkColor: _q2Color,
                onSelected: (v) => setDlgState(() => important = v),
              ),
            ]),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                onUpdate(ctrl.text, urgent, important);
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasQuadrant = task.urgent || task.important;
    return Dismissible(
      key: Key(task.uid.isNotEmpty ? task.uid : task.title),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.redAccent,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete task?'),
          content: Text(task.title),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete',
                    style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: Checkbox(value: task.done, onChanged: (_) => onToggle()),
        title: Row(children: [
          if (hasQuadrant)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _quadrantColor(task.urgent, task.important),
                shape: BoxShape.circle,
              ),
            ),
          Expanded(
            child: Text(
              task.title,
              style: TextStyle(
                decoration:
                    task.done ? TextDecoration.lineThrough : null,
                color: task.done ? Colors.grey : null,
              ),
            ),
          ),
        ]),
        subtitle: task.description.isNotEmpty
            ? Text(task.description,
                maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        onLongPress: () => _showEditDialog(context),
      ),
    );
  }
}

// ── Eisenhower Matrix view ────────────────────────────────────────────────────
class _MatrixView extends StatelessWidget {
  final AppState state;
  final int wsIndex;
  const _MatrixView({required this.state, required this.wsIndex});

  List<Task> _q(bool urgent, bool important) {
    if (wsIndex >= state.workspaces.length) return [];
    return state.workspaces[wsIndex].tasks
        .where((t) => t.urgent == urgent && t.important == important)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(children: [
        Expanded(
          child: Row(children: [
            Expanded(
                child: _QuadrantCard(
                    label: 'Do First',
                    subtitle: 'Urgent + Important',
                    color: _q1Color,
                    tasks: _q(true, true),
                    wsIndex: wsIndex,
                    state: state)),
            const SizedBox(width: 4),
            Expanded(
                child: _QuadrantCard(
                    label: 'Schedule',
                    subtitle: 'Important, not Urgent',
                    color: _q2Color,
                    tasks: _q(false, true),
                    wsIndex: wsIndex,
                    state: state)),
          ]),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Row(children: [
            Expanded(
                child: _QuadrantCard(
                    label: 'Delegate',
                    subtitle: 'Urgent, not Important',
                    color: _q3Color,
                    tasks: _q(true, false),
                    wsIndex: wsIndex,
                    state: state)),
            const SizedBox(width: 4),
            Expanded(
                child: _QuadrantCard(
                    label: 'Eliminate',
                    subtitle: 'Neither',
                    color: _q4Color,
                    tasks: _q(false, false),
                    wsIndex: wsIndex,
                    state: state)),
          ]),
        ),
      ]),
    );
  }
}

class _QuadrantCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;
  final List<Task> tasks;
  final int wsIndex;
  final AppState state;

  const _QuadrantCard({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.tasks,
    required this.wsIndex,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(children: [
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: color,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 10)),
              ]),
        ),
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Text('Empty',
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 12)))
              : ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (ctx, i) {
                    final task = tasks[i];
                    final allTasks =
                        state.workspaces[wsIndex].tasks;
                    final idx = allTasks
                        .indexWhere((t) => t.uid == task.uid);
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      leading: SizedBox(
                        width: 24,
                        child: Checkbox(
                          value: task.done,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: idx >= 0
                              ? (_) =>
                                  state.toggleTask(wsIndex, idx)
                              : null,
                        ),
                      ),
                      title: Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 12,
                          decoration: task.done
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.done ? Colors.grey : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
