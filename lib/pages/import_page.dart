import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../auto_category.dart';
import '../db.dart';
import '../icons.dart';
import '../import/ai_parser.dart';
import '../import/alipay_parser.dart';
import '../import/wechat_parser.dart';
import '../models.dart';
import '../widgets/common.dart';

class ImportPage extends StatefulWidget {
  final TxnDao dao;

  const ImportPage({super.key, required this.dao});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

typedef _ParseFn = Future<ParseResult?> Function(List<int> bytes);

class _ImportPageState extends State<ImportPage> {
  String? _fileName;
  String? _picked;

  String? _methodError;

  ParseResult? _result;
  AiTrace? _trace;
  String? _error;
  bool _busy = false;

  late final Map<String, _ParseFn> _methods = {
    '微信': (b) async => parseWechat(b),
    '支付宝': (b) async => parseAlipay(b),
    '大模型': _parseAi,
  };

  Future<ParseResult?> _parseAi(List<int> bytes) async {
    final cfg = AiConfig.fromSettings(await widget.dao.settings());
    return parseAi(
      bytes,
      cfg,
      onTrace: (t) {
        if (mounted) setState(() => _trace = t);
      },
    );
  }

  String get _recordName {
    final n = _fileName;
    if (n == null) return '导入';
    final dot = n.lastIndexOf('.');
    return dot > 0 ? n.substring(0, dot) : n;
  }

  Future<void> _choose(String method) async {
    final parse = _methods[method];
    if (parse == null) return;

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'tsv', 'txt', 'xlsx'],
    );
    if (file == null) return;

    final path = file.path;
    if (path == null) {
      if (mounted) setState(() => _error = '读不到文件路径');
      return;
    }

    setState(() {
      _picked = method;
      _busy = true;
      _error = null;
      _methodError = null;
      _result = null;
      _trace = null;
    });
    try {
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      setState(() => _fileName = file.name);

      final result = await parse(bytes);
      if (!mounted) return;
      setState(() {
        _result = result;
        _methodError = result == null ? '「$method」认不出这份文件' : null;
        _error = (result != null && result.txns.isEmpty)
            ? result.issues.map((e) => e.toString()).join('\n')
            : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '解析失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmImport() async {
    final r = _result;
    if (r == null || r.txns.isEmpty) return;

    setState(() => _busy = true);
    try {
      final rules = await widget.dao.categoryRules();
      final n = await widget.dao.insertAll(
        applyRules(r.txns, rules),
        source: _recordName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导入 $n 条流水')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '写入失败：$e';
        });
      }
    }
  }

  List<Widget> _methodRows() => [
    for (final n in _methods.keys) ...[
      ListTile(
        title: Text(n),
        trailing: Icon(AppIcons.resolve('chevronRight')),
        selected: _picked == n,
        onTap: _busy ? null : () => _choose(n),
      ),
      const Divider(height: 1),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final name = _fileName;

    return Scaffold(
      appBar: AppBar(title: const Text('导入账单')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          ..._methodRows(),
          if (name != null) _HintText(text: '已选文件：$name', isError: false),
          if (_busy) const LinearProgressIndicator(),
          if (_trace != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: AiTraceView(
                    trace: _trace!,
                    outcome: (r != null && r.txns.isNotEmpty)
                        ? '${r.dataRowCount} 行 → ${r.txns.length} 条流水'
                              '${r.skipped > 0 ? '，${r.skipped} 条认不出' : ''}'
                        : null,
                  ),
                ),
              ),
            ),
          if (_methodError != null)
            _HintText(text: _methodError!, isError: true),
          if (_error != null) _HintText(text: _error!, isError: true),
          if (r != null && r.txns.isNotEmpty) ...[
            if (_trace == null)
              _HintText(
                text:
                    '${r.sourceName}：识别到 ${r.txns.length} 条'
                    '${r.skipped > 0 ? '，跳过 ${r.skipped} 条' : ''}',
                isError: false,
              ),
            if (r.skipped > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    r.issues.take(3).map((e) => e.toString()).join('\n'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: r.txns.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _PreviewTile(txn: r.txns[i]),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
      bottomNavigationBar: r == null || r.txns.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _busy ? null : _confirmImport,
                  child: Text('确认导入 ${r.txns.length} 条'),
                ),
              ),
            ),
    );
  }
}

class _HintText extends StatelessWidget {
  final String text;
  final bool isError;

  const _HintText({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        text,
        style: TextStyle(color: isError ? cs.error : cs.onSurfaceVariant),
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  final Txn txn;

  const _PreviewTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      title: Text(
        '${txn.counterparty ?? '未知'}'
        '${txn.item == null ? '' : ' · ${txn.item}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${txn.date}  ${txn.category ?? '未分类'}'
        '${txn.type == null ? '' : '  ${txn.type}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${txn.isExpense ? '-' : '+'}${formatCents(txn.amountCents)}',
        style: TextStyle(
          color: txn.isExpense ? cs.error : cs.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
