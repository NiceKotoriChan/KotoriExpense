import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';
import '../models.dart';
import '../stats.dart' show isoDate;

class TxnEditPage extends StatefulWidget {
  final TxnDao dao;
  final Txn? txn;

  const TxnEditPage({super.key, required this.dao, this.txn});

  bool get isNew => txn == null;

  @override
  State<TxnEditPage> createState() => _TxnEditPageState();
}

class _TxnEditPageState extends State<TxnEditPage> {
  late DateTime _when;
  late bool _expense;
  bool _busy = false;
  String? _error;
  Map<String, String> _categoryIcons = const {};

  final _amount = TextEditingController();
  final _currency = TextEditingController();
  final _type = TextEditingController();
  final _counterparty = TextEditingController();
  final _item = TextEditingController();
  final _category = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadIcons();
    final t = widget.txn;
    if (t == null) {
      _when = DateTime.now();
      _expense = true;
      _currency.text = 'CNY';
    } else {
      _when = DateTime.tryParse(t.date) ?? DateTime.now();
      _expense = t.isExpense;
      _currency.text = t.currency;
      _amount.text = (t.amountCents / 100).toStringAsFixed(2);
      _type.text = t.type ?? '';
      _counterparty.text = t.counterparty ?? '';
      _item.text = t.item ?? '';
      _category.text = t.category ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _amount,
      _currency,
      _type,
      _counterparty,
      _item,
      _category,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadIcons() async {
    final m = await widget.dao.categoryIcons();
    if (mounted) setState(() => _categoryIcons = m);
  }

  String get _dateText => isoDate(_when.year, _when.month, _when.day);

  String? _trimmed(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    setState(() => _when = d);
  }

  Future<void> _pickCategory() async {
    final list = await widget.dao.knownCategories();
    if (!mounted) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: Icon(AppIcons.resolve('clear')),
            title: const Text('不填分类'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
          const Divider(height: 1),
          for (final c in list)
            ListTile(
              leading: Icon(
                AppIcons.resolve(iconNameForCategory(c, _categoryIcons)),
              ),
              title: Text(c),
              onTap: () => Navigator.pop(ctx, c),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _category.text = picked);
  }

  Future<void> _save() async {
    final cents = parseAmountCents(_amount.text)?.abs();
    if (cents == null || cents == 0) {
      setState(() => _error = '金额要填一个大于 0 的数');
      return;
    }

    final txn = Txn(
      id: widget.txn?.id,
      date: _dateText,
      currency: _currency.text.trim().isEmpty ? 'CNY' : _currency.text.trim(),
      type: _trimmed(_type),
      counterparty: _trimmed(_counterparty),
      item: _trimmed(_item),
      direction: _expense ? 'expense' : 'income',
      amountCents: cents,
      category: _trimmed(_category),
    );

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.isNew) {
        await widget.dao.insert(txn, source: kManualRecordName);
      } else {
        await widget.dao.update(txn);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败：$e';
        });
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.txn?.id;
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条流水？'),
        content: Text(
          '${widget.txn!.counterparty ?? widget.txn!.item ?? '这条记录'}\n'
          '${formatCents(widget.txn!.amountCents)}，删了拿不回来。',
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

    setState(() => _busy = true);
    try {
      await widget.dao.deleteTxn(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '删除失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? '记一笔' : '账单详情'),
        actions: [
          if (!widget.isNew)
            IconButton(
              onPressed: _busy ? null : _delete,
              icon: Icon(AppIcons.resolve('deleteTxn')),
              tooltip: '删除',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('支出')),
                ButtonSegment(value: false, label: Text('收入')),
              ],
              selected: {_expense},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _expense = s.first),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: widget.isNew,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: const InputDecoration(
              labelText: '金额',
              prefixText: '¥ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _DateRow(
            icon: AppIcons.resolve('event'),
            label: '日期',
            value: _dateText,
            onTap: _busy ? null : _pickDate,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _category,
            decoration: InputDecoration(
              labelText: '分类',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: _busy ? null : _pickCategory,
                icon: Icon(AppIcons.resolve('arrowDropDown')),
                tooltip: '从已有分类里选',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _counterparty,
            decoration: const InputDecoration(
              labelText: '交易对象',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _item,
            decoration: const InputDecoration(
              labelText: '交易商品',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _type,
            decoration: const InputDecoration(
              labelText: '交易类型',
              helperText: '付款方式 / 交易摘要',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currency,
            decoration: const InputDecoration(
              labelText: '货币',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(widget.isNew ? '记下' : '保存修改'),
          ),
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _DateRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text(label, style: tt.bodyMedium),
      trailing: Text(value, style: tt.bodyLarge),
      onTap: onTap,
    );
  }
}
