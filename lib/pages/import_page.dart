import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';
import '../import/alipay_parser.dart';
import '../import/default_parser.dart';
import '../import/wechat_parser.dart';
import '../models.dart';
import 'bill_rules_page.dart';

/// 选账单文件 -> 选解析方式 -> 预览 -> 确认入库。
///
/// 不做自动嗅探：文件选完一个方式都不预选，用户点哪个就用哪个。
class ImportPage extends StatefulWidget {
  final TxnDao dao;

  const ImportPage({super.key, required this.dao});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

/// 内置的两家。列名硬编码在各自 parser 里，所以没有「配置」这一步。
const List<String> _builtinMethods = ['微信', '支付宝'];

const String _builtinPrefix = 'builtin:';
const String _rulePrefix = 'rule:';

class _ImportPageState extends State<ImportPage> {
  String? _fileName;
  List<int>? _bytes;

  List<BillRule> _rules = const [];

  /// 选中的解析方式，见 [_builtinPrefix] / [_rulePrefix]
  String? _picked;

  /// 选中的方式认不出这份文件
  String? _methodError;

  ParseResult? _result;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final rules = await widget.dao.rules();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      // 选中的那条可能刚被删掉
      if (_picked != null && _labelOf(_picked!) == null) {
        _picked = null;
        _result = null;
        _methodError = null;
      }
    });
  }

  /// 解析方式的键 -> 显示名；不存在返回 null
  String? _labelOf(String key) {
    if (key.startsWith(_builtinPrefix)) {
      final n = key.substring(_builtinPrefix.length);
      return _builtinMethods.contains(n) ? n : null;
    }
    final name = key.substring(_rulePrefix.length);
    for (final r in _rules) {
      if (r.name == name) return name;
    }
    return null;
  }

  ParseResult? _parseWith(String key, List<int> bytes) {
    if (key.startsWith(_builtinPrefix)) {
      return key.substring(_builtinPrefix.length) == '微信'
          ? parseWechat(bytes)
          : parseAlipay(bytes);
    }
    final name = key.substring(_rulePrefix.length);
    return parseDefault(bytes, _rules.firstWhere((r) => r.name == name));
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
      _methodError = null;
    });
    try {
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
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _bytes = bytes;
        // 换了文件，解析方式得重新选
        _picked = null;
        _result = null;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '读文件失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(String key) async {
    final bytes = _bytes;
    if (bytes == null) return;

    setState(() {
      _picked = key;
      _busy = true;
      _error = null;
      _methodError = null;
      _result = null;
    });
    try {
      final result = _parseWith(key, bytes);
      if (!mounted) return;
      setState(() {
        _result = result;
        _methodError = result == null ? '「${_labelOf(key)}」认不出这份文件' : null;
        // 认得出来但一条都没成，把原因摆出来
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

  Future<void> _openRules() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => BillRulesPage(dao: widget.dao)));
    await _loadRules();
  }

  Future<void> _confirmImport() async {
    final r = _result;
    if (r == null || r.txns.isEmpty) return;

    setState(() => _busy = true);
    try {
      final n = await widget.dao.insertAll(r.txns);
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

  List<Widget> _methodChips() => [
    for (final n in _builtinMethods)
      ChoiceChip(
        label: Text(n),
        selected: _picked == '$_builtinPrefix$n',
        onSelected: _busy ? null : (_) => _choose('$_builtinPrefix$n'),
      ),
    for (final r in _rules)
      ChoiceChip(
        label: Text(r.name),
        selected: _picked == '$_rulePrefix${r.name}',
        onSelected: _busy ? null : (_) => _choose('$_rulePrefix${r.name}'),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final r = _result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('导入账单'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _openRules,
            icon: Icon(AppIcons.resolve('tableChart')),
            tooltip: '管理解析方式',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: Icon(AppIcons.resolve('pickFile')),
              label: Text(
                _fileName ?? '选择账单文件（CSV / TSV / XLSX）',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (_bytes != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text('用哪种方式解析？', style: tt.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(spacing: 8, runSpacing: 4, children: _methodChips()),
            ),
            if (_rules.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  '自定义解析方式在右上角「管理解析方式」里加。',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_methodError != null)
            _HintText(text: _methodError!, isError: true),
          if (_error != null) _HintText(text: _error!, isError: true),
          if (r != null && r.txns.isNotEmpty) ...[
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
