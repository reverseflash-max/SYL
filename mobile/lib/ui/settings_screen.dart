import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'widgets/common.dart';

/// The AI on your PC and sync with your PC, each saved on its own.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _model;
  late final TextEditingController _syncUrl;
  late final TextEditingController _syncCode;
  String? _status;
  String? _syncStatus;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<LibraryStore>().settings;
    _url = TextEditingController(text: s.lmStudioUrl);
    _model = TextEditingController(text: s.lmModel);
    _syncUrl = TextEditingController(text: s.syncUrl);
    _syncCode = TextEditingController(text: s.syncCode);
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _syncUrl.dispose();
    _syncCode.dispose();
    super.dispose();
  }

  Future<void> _saveAi() async {
    final store = context.read<LibraryStore>();
    await store.updateSettings(store.settings.copyWith(lmStudioUrl: _url.text.trim(), lmModel: _model.text.trim()));
    if (mounted) showMessage(context, 'AI settings saved');
  }

  Future<void> _saveSync() async {
    final store = context.read<LibraryStore>();
    await store.updateSettings(store.settings.copyWith(syncUrl: _syncUrl.text.trim(), syncCode: _syncCode.text.trim()));
    if (mounted) showMessage(context, 'Sync settings saved');
  }

  Future<void> _sync() async {
    final store = context.read<LibraryStore>();
    setState(() => _syncStatus = null);
    await store.updateSettings(store.settings.copyWith(syncUrl: _syncUrl.text.trim(), syncCode: _syncCode.text.trim()));
    String msg;
    try {
      msg = await store.syncWithPc();
    } catch (e) {
      msg = e.toString();
    }
    if (mounted) setState(() => _syncStatus = msg);
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    final ai = context.read<LibraryStore>().ai;
    try {
      final models = await ai.listModels(_url.text.trim());
      final chosen = await ai.pickModel(_url.text.trim(), _model.text.trim());
      _status = 'Connected. Loaded: ${models.join(', ')}\nSYL will use: $chosen';
    } catch (e) {
      _status = e.toString();
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final t = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
        children: [
          Text('Settings', style: t.displaySmall?.copyWith(fontSize: 44)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Syl.white, borderRadius: Syl.r24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('AI on your PC', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'SYL uses the model loaded in LM Studio. On the PC, use http://127.0.0.1 and LM Studio\'s port '
                '(usually 1234). On your phone, use the same address as Sync with your PC below, while '
                'python syl.py serve is running: the PC passes AI requests on to LM Studio.',
                style: TextStyle(fontSize: 13, color: Syl.muted),
              ),
              const SizedBox(height: 14),
              TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'LM Studio address')),
              const SizedBox(height: 10),
              TextField(
                controller: _model,
                decoration: const InputDecoration(labelText: 'Model (optional)', hintText: 'Blank = whatever is loaded'),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                PillButton(label: _testing ? 'Testing...' : 'Test connection', icon: Icons.wifi_tethering, onTap: _testing ? null : _test),
                PillButton(label: 'Save', icon: Icons.check, dark: true, onTap: _saveAi),
              ]),
              if (_status != null) ...[
                const SizedBox(height: 10),
                Text(_status!, style: const TextStyle(fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Syl.white, borderRadius: Syl.r24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Sync with your PC', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'On the PC run: python syl.py serve. It shows the address and pairing code to enter here. '
                'Both devices need to be on the same Wi-Fi. Entries, facts, links, books and deletions are merged both ways.',
                style: TextStyle(fontSize: 13, color: Syl.muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _syncUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'PC sync address', hintText: 'http://<your PC IP>:8765'),
              ),
              const SizedBox(height: 10),
              TextField(controller: _syncCode, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pairing code')),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                PillButton(label: store.syncing ? 'Syncing...' : 'Sync now', icon: Icons.sync, onTap: store.syncing ? null : _sync),
                PillButton(label: 'Save', icon: Icons.check, dark: true, onTap: _saveSync),
              ]),
              if (_syncStatus != null) ...[
                const SizedBox(height: 10),
                Text(_syncStatus!, style: const TextStyle(fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(height: 18),
          Text('Library folder: ${store.dataPath}', style: TextStyle(fontSize: 12, color: Syl.muted)),
        ],
      ),
    );
  }
}
