import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../icons.dart';
import '../db.dart';
import '../import/bill_parser.dart';
import '../models.dart';

/// 选账单文件 -> 解析预览 -> 确认入库
class ImportPage extends StatefulWidget {
  final TxnDao dao;

  const ImportPage({super.key, required this.dao});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  String? _fileName;
  ParseResult? _result;
  String? _error;
  bool _busy = false;

  /// 设置页改过的列名映射，导入时按它解析
  BillRules _rules = kDefaultBillRules;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final r = await widget.dao.csvRules();
    if (mounted) setState(() => _rules = r);
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
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

      final result = parseBillBytes(bytes, _rules);
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _result = result;
        // 一条都没解析出来时，直接把原因摆出来
        _error = result.txns.isEmpty
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

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('导入账单')),
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
          if (_busy) const LinearProgressIndicator(),
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
