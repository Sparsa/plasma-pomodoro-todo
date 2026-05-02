import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class GoogleSettingsScreen extends StatefulWidget {
  const GoogleSettingsScreen({super.key});

  @override
  State<GoogleSettingsScreen> createState() => _GoogleSettingsScreenState();
}

class _GoogleSettingsScreenState extends State<GoogleSettingsScreen> {
  late TextEditingController _clientIdCtrl;
  bool _autoSync = false;
  bool _isSigning = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _clientIdCtrl = TextEditingController(text: s.googleClientId);
    _autoSync = s.googleAutoSync;
  }

  @override
  void dispose() {
    _clientIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final s = context.read<AppState>();
    // Save client ID before auth so GoogleAuthService uses the new value.
    await s.saveGoogleSettings(
      clientId: _clientIdCtrl.text.trim(),
      autoSync: _autoSync,
    );
    setState(() => _isSigning = true);
    final err = await s.signInGoogle();
    setState(() => _isSigning = false);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out of Google?'),
        content: const Text('Workspace-to-list assignments will be kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign out',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AppState>().signOutGoogle();
    }
  }

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    await context.read<AppState>().syncGoogle();
    setState(() => _isSyncing = false);
  }

  Future<void> _save() async {
    await context.read<AppState>().saveGoogleSettings(
          clientId: _clientIdCtrl.text.trim(),
          autoSync: _autoSync,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isConnected = state.googleEmail != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Tasks'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Client ID ────────────────────────────────────────────────────
          const Text(
            'OAuth2 Client ID',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _clientIdCtrl,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              hintText: '…apps.googleusercontent.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Google Cloud Console → APIs & Services → Credentials → Desktop app client ID.\n'
            'Enable the "Tasks API" under Library.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),

          const Divider(height: 32),

          // ── Sign in / out ─────────────────────────────────────────────────
          if (!isConnected) ...[
            FilledButton.icon(
              onPressed: _isSigning ? null : _signIn,
              icon: _isSigning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.login),
              label: const Text('Sign in with Google'),
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_circle, size: 40),
              title: Text(state.googleEmail!),
              subtitle: const Text('Connected'),
              trailing: TextButton(
                onPressed: _signOut,
                child: const Text('Sign out',
                    style: TextStyle(color: Colors.red)),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isSyncing ? null : _syncNow,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 18),
              label: const Text('Sync now'),
            ),
            if (state.googleSyncMessage.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                state.googleSyncMessage,
                style: TextStyle(
                  fontSize: 13,
                  color: state.googleSyncStatus == SyncStatus.error
                      ? Colors.red
                      : Colors.green,
                ),
              ),
            ],
          ],

          const Divider(height: 32),

          // ── Auto-sync ─────────────────────────────────────────────────────
          SwitchListTile(
            title: const Text('Auto-sync'),
            subtitle: const Text('Sync 2 s after task changes'),
            value: _autoSync,
            onChanged: (v) => setState(() => _autoSync = v),
            contentPadding: EdgeInsets.zero,
          ),

          const Divider(height: 32),

          // ── Workspace → task list mapping ─────────────────────────────────
          if (isConnected) ...[
            const Text(
              'Workspace → Task List',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose which Google Tasks list each workspace syncs with.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ...List.generate(state.workspaces.length, (i) {
              return _WorkspaceListPicker(wsIndex: i);
            }),
          ],
        ],
      ),
    );
  }
}

// ── Workspace → Task List picker row ──────────────────────────────────────────
class _WorkspaceListPicker extends StatefulWidget {
  final int wsIndex;
  const _WorkspaceListPicker({required this.wsIndex});

  @override
  State<_WorkspaceListPicker> createState() => _WorkspaceListPickerState();
}

class _WorkspaceListPickerState extends State<_WorkspaceListPicker> {
  List<Map<String, dynamic>>? _lists;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lists = await context.read<AppState>().listGoogleTaskLists();
      if (mounted) setState(() { _lists = lists; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ws = state.workspaces[widget.wsIndex];

    if (_loading) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(ws.name),
        trailing: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_error != null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(ws.name),
        subtitle: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }

    final lists = _lists!;
    final items = [
      const DropdownMenuItem<String>(
          value: '', child: Text('— not synced —')),
      ...lists.map((l) => DropdownMenuItem<String>(
            value: l['id'] as String,
            child: Text(l['title'] as String? ?? l['id'] as String),
          )),
    ];

    String currentValue = ws.googleTaskListId;
    if (currentValue.isNotEmpty &&
        !lists.any((l) => l['id'] == currentValue)) {
      currentValue = '';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        SizedBox(width: 110, child: Text(ws.name, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: currentValue,
            items: items,
            onChanged: (v) {
              context
                  .read<AppState>()
                  .setWorkspaceGoogleList(widget.wsIndex, v ?? '');
            },
          ),
        ),
      ]),
    );
  }
}
