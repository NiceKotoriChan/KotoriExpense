import 'package:flutter/material.dart';

import '../bill_visibility.dart';
import '../db.dart';
import '../icons.dart';
import '../models.dart';
import '../widgets/common.dart';

class RecordsPage extends StatefulWidget {
  final TxnDao dao;
  final BillVisibility visibility;
  final VoidCallback? onDataChanged;

  const RecordsPage({
    super.key,
    required this.dao,
    required this.visibility,
    this.onDataChanged,
  });

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  List<RecordSummary>? _records;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.dao.recordSummaries();
    if (mounted) setState(() => _records = r);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(RecordSummary record, bool shown) async {
    final saved = widget.visibility.setHidden(record.id, !shown);
    if (!mounted) return;
    setState(() {});
    widget.onDataChanged?.call();
    await saved;
  }

  Future<void> _rename(RecordSummary record) async {
    final name = await showTextDialog(
      context,
      title: '账单名字',
      initial: record.name,
      hint: '改个自己能认出来的名字',
    );
    if (name == null || name.isEmpty || name == record.name) return;

    try {
      await widget.dao.renameRecord(record.id, name);
    } catch (e) {
      if (!mounted) return;
      _toast(
        '$e'.contains('UNIQUE') ? '已经有同名的账单了' : '改名失败：$e',
      );
      return;
    }
    if (!mounted) return;
    widget.onDataChanged?.call();
    await _load();
  }

  Future<void> _delete(RecordSummary record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这份账单？'),
        content: Text(
          '${record.name}\n'
          '${record.count} 笔流水会一起删掉，拿不回来。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await widget.dao.deleteRecord(record.id);
    if (widget.visibility.isHidden(record.id)) {
      widget.visibility.setHidden(record.id, false).ignore();
    }
    if (!mounted) return;
    widget.onDataChanged?.call();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rows = _records;

    return Scaffold(
      appBar: AppBar(title: const Text('管理账单')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.resolve('emptyState'),
                    size: 48,
                    color: cs.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '还没有导入过账单',
                    style: tt.bodyMedium?.copyWith(color: cs.outline),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _RecordTile(
                record: rows[i],
                shown: !widget.visibility.isHidden(rows[i].id),
                onToggle: (v) => _toggle(rows[i], v),
                onRename: () => _rename(rows[i]),
                onDelete: () => _delete(rows[i]),
              ),
            ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final RecordSummary record;
  final bool shown;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _RecordTile({
    required this.record,
    required this.shown,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final balance = record.balanceCents;

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      leading: Switch(value: shown, onChanged: onToggle),
      title: Text(
        record.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyLarge?.copyWith(
          color: shown ? null : cs.onSurfaceVariant,
        ),
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${record.count} 笔流水 · 结余 '),
            TextSpan(
              text: formatCents(balance),
              style: TextStyle(
                color: balance < 0 ? cs.error : cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        onPressed: onDelete,
        icon: Icon(AppIcons.resolve('deleteTxn'), color: cs.onSurfaceVariant),
        tooltip: '删除',
      ),
      onLongPress: onRename,
    );
  }
}
