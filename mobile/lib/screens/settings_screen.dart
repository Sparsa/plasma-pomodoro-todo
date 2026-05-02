import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../services/settings_service.dart';
import '../services/webdav_service.dart';
import 'google_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlCtrl;
  late TextEditingController _userCtrl;
  final _passCtrl = TextEditingController();

  bool _autoSync = false;
  int _interval = 5;
  int _pomodoroMin = 25;
  int _shortBreakMin = 5;
  int _longBreakMin = 15;
  bool _obscurePass = true;

  String _testResult = '';
  bool _testOk = false;
  bool _isTesting = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _urlCtrl = TextEditingController(text: s.webdavUrl);
    _userCtrl = TextEditingController(text: s.webdavUsername);
    _autoSync = s.webdavAutoSync;
    _interval = s.webdavInterval;
    _pomodoroMin = s.pomodoroMinutes;
    _shortBreakMin = s.shortBreakMinutes;
    _longBreakMin = s.longBreakMinutes;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() {
        _testResult = 'Enter a file URL first.';
        _testOk = false;
      });
      return;
    }
    setState(() {
      _isTesting = true;
      _testResult = '';
    });

    final savedPass = await SettingsService.getPassword();
    final pass =
        _passCtrl.text.isNotEmpty ? _passCtrl.text : (savedPass ?? '');
    final svc = WebDavService(
        fileUrl: url, username: _userCtrl.text.trim(), password: pass);
    final (ok, msg) = await svc.testConnection();

    setState(() {
      _isTesting = false;
      _testOk = ok;
      _testResult = msg;
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await context.read<AppState>().saveSettings(
          url: _urlCtrl.text.trim(),
          username: _userCtrl.text.trim(),
          password: _passCtrl.text.isNotEmpty ? _passCtrl.text : null,
          autoSync: _autoSync,
          interval: _interval,
          pomodoroMin: _pomodoroMin,
          shortBreakMin: _shortBreakMin,
          longBreakMin: _longBreakMin,
        );
    setState(() => _isSaving = false);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── WebDAV ───────────────────────────────────────────────────────
          _SectionHeader('WebDAV'),
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'File URL',
              hintText:
                  'https://cloud.example.com/.../pomodoro-tasks.json',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Full URL to the JSON file on your WebDAV server.\n'
            'Nextcloud: …/remote.php/dav/files/user/pomodoro-tasks.json',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(
                labelText: 'Username', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: _obscurePass,
            decoration: InputDecoration(
              labelText: state.hasPassword
                  ? 'Password (saved — enter to replace)'
                  : 'Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscurePass ? Icons.visibility : Icons.visibility_off),
                onPressed: () =>
                    setState(() => _obscurePass = !_obscurePass),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _isTesting ? null : _test,
              icon: _isTesting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering, size: 16),
              label: const Text('Test Connection'),
            ),
          ]),
          if (_testResult.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _testResult,
              style: TextStyle(
                  color: _testOk ? Colors.green : Colors.red, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Auto-sync'),
            subtitle: const Text(
                'Push 2 s after changes; pull on interval'),
            value: _autoSync,
            onChanged: (v) => setState(() => _autoSync = v),
            contentPadding: EdgeInsets.zero,
          ),
          if (_autoSync) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Text('Sync every '),
              DropdownButton<int>(
                value: _interval,
                items: [1, 2, 5, 10, 15, 30, 60]
                    .map((v) => DropdownMenuItem(
                        value: v, child: Text('$v min')))
                    .toList(),
                onChanged: (v) => setState(() => _interval = v!),
              ),
            ]),
          ],

          const Divider(height: 32),

          // ── Timer ────────────────────────────────────────────────────────
          _SectionHeader('Timer'),
          const SizedBox(height: 8),
          _MinutesRow(
            label: 'Focus',
            value: _pomodoroMin,
            onChanged: (v) => setState(() => _pomodoroMin = v),
          ),
          _MinutesRow(
            label: 'Short break',
            value: _shortBreakMin,
            onChanged: (v) => setState(() => _shortBreakMin = v),
          ),
          _MinutesRow(
            label: 'Long break',
            value: _longBreakMin,
            onChanged: (v) => setState(() => _longBreakMin = v),
          ),

          const Divider(height: 32),

          // ── Google Tasks ─────────────────────────────────────────────────
          _SectionHeader('Google Tasks'),
          const SizedBox(height: 8),
          Builder(builder: (ctx) {
            final s = context.watch<AppState>();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('Google Tasks sync'),
              subtitle: Text(s.googleEmail ?? 'Not connected'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const GoogleSettingsScreen()),
              ),
            );
          }),

          const Divider(height: 32),

          // ── About ────────────────────────────────────────────────────────
          _SectionHeader('About'),
          const SizedBox(height: 8),
          const Text(
            'Companion app for the KDE Plasma Pomodoro Todo plasmoid.\n'
            'Tasks sync via a shared JSON file on your WebDAV server.\n\n'
            'Long-press a task to rename it.\n'
            'Swipe left to delete.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      );
}

class _MinutesRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _MinutesRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 100, child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 56,
            child: Text('$value min',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: value < 120 ? () => onChanged(value + 1) : null,
          ),
        ]),
      );
}
