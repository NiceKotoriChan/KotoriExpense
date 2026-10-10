import 'dart:async';

import 'package:flutter/material.dart';

import '../db.dart';
import '../import/ai_parser.dart';
import '../widgets/common.dart';

class AiConfigPage extends StatefulWidget {
  final TxnDao dao;

  const AiConfigPage({super.key, required this.dao});

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  static const Duration _saveDelay = Duration(milliseconds: 600);

  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  final _prompt = TextEditingController();

  Timer? _pendingSave;
  bool _loaded = false;
  bool _busy = false;
  AiTrace? _trace;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _flushSave();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await widget.dao.settings();
    if (!mounted) return;
    setState(() {
      _baseUrl.text = s[kAiBaseUrl] ?? '';
      _apiKey.text = s[kAiApiKey] ?? '';
      _model.text = s[kAiModel] ?? '';
      _prompt.text = s[kAiPrompt] ?? kDefaultAiPrompt;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await widget.dao.saveSettings({
      kAiBaseUrl: _baseUrl.text.trim(),
      kAiApiKey: _apiKey.text.trim(),
      kAiModel: _model.text.trim(),
      kAiPrompt: _prompt.text.trim(),
    });
  }

  void _scheduleSave() {
    _pendingSave?.cancel();
    _pendingSave = Timer(_saveDelay, _save);
  }

  void _flushSave() {
    if (_pendingSave == null || !_pendingSave!.isActive) return;
    _pendingSave!.cancel();
    _save();
  }

  Future<void> _test() async {
    final cfg = AiConfig(
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim(),
      prompt: _prompt.text.trim(),
    );

    setState(() {
      _busy = true;
      _trace = null;
    });

    final trace = await aiExchange(cfg, 'hi', timeout: kAiProbeTimeout);
    if (!mounted) return;
    setState(() {
      _trace = trace;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型配置')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _baseUrl,
                  onChanged: (_) => _scheduleSave(),
                  decoration: const InputDecoration(
                    labelText: 'API 地址',
                    hintText: 'https://api.openai.com/v1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKey,
                  obscureText: true,
                  onChanged: (_) => _scheduleSave(),
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  onChanged: (_) => _scheduleSave(),
                  decoration: const InputDecoration(
                    labelText: '模型名',
                    hintText: 'gpt-4o-mini',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _prompt,
                  minLines: 6,
                  maxLines: 14,
                  onChanged: (_) => _scheduleSave(),
                  decoration: const InputDecoration(
                    labelText: '提示词',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _test,
                    child: const Text('测试连接'),
                  ),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_trace != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: AiTraceView(trace: _trace!),
                  ),
              ],
            ),
    );
  }
}
