import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';
import '../models.dart';

/// 解析方式管理。
///
/// 微信 / 支付宝的列名硬编码在各自 parser 里，所以它们是只读的内置项；
/// 自定义的存 rules 表，可以增删改 —— 一条自定义方式就是「把文件里的列名
/// 对应到表的列名」。
class BillRulesPage extends StatefulWidget {
  final TxnDao dao;

  const BillRulesPage({super.key, required this.dao});

  @override
  State<BillRulesPage> createState() => _BillRulesPageState();
}

class _BillRulesPageState extends State<BillRulesPage> {
  List<BillRule> _rules = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.dao.rules();
    if (!mounted) return;
    setState(() {
      _rules = r;
      _loading = false;
    });
  }

  Future<void> _edit([BillRule? rule]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BillRuleEditPage(
          dao: widget.dao,
          rule: rule,
          takenNames: [for (final r in _rules) r.name],
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(BillRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删掉这个解析方式？'),
        content: Text('「${rule.name}」删了拿不回来。已经导入的流水不受影响。'),
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
    await widget.dao.deleteRule(rule.name);
    await _load();
  }

  /// 副标题：把配好的列摊开，一眼看出这条规则在干什么
  String _summary(BillRule rule) {
    final pairs = [
      for (final c in BillRule.columns)
        if (rule.header(c) != null) '${BillRule.labels[c]}＝${rule.header(c)}',
    ];
    return '${rule.isUsable ? '' : '还缺必需列 · '}${pairs.join('  ')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('解析方式')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                for (final n in const ['微信', '支付宝'])
                  ListTile(
                    enabled: false,
                    leading: Icon(AppIcons.resolve('importBill')),
                    title: Text(n),
                    subtitle: const Text('内置，列名写死在代码里，改不了'),
                  ),
                const Divider(height: 24),
                if (_rules.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Text('还没有自定义解析方式。点右下角加一条，把文件里的列名对应到表的列名。'),
                  ),
                for (final r in _rules)
                  ListTile(
                    leading: Icon(AppIcons.resolve('tableChart')),
                    title: Text(r.name),
                    subtitle: Text(
                      _summary(r),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      onPressed: () => _delete(r),
                      icon: Icon(AppIcons.resolve('deleteTxn')),
                      tooltip: '删除',
                    ),
                    onTap: () => _edit(r),
                  ),
                const SizedBox(height: 72),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        tooltip: '新建解析方式',
        child: Icon(AppIcons.resolve('addRule')),
      ),
    );
  }
}

/// 新建 / 编辑一条自定义解析方式。自己存库，存完 pop(true)。
class BillRuleEditPage extends StatefulWidget {
  final TxnDao dao;
  final BillRule? rule;
  final List<String> takenNames;

  const BillRuleEditPage({
    super.key,
    required this.dao,
    this.rule,
    this.takenNames = const [],
  });

  @override
  State<BillRuleEditPage> createState() => _BillRuleEditPageState();
}

class _BillRuleEditPageState extends State<BillRuleEditPage> {
  final _name = TextEditingController();
  final _fields = {
    for (final c in BillRule.columns) c: TextEditingController(),
  };
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _name.text = r?.name ?? BillRule.nextName(widget.takenNames);
    if (r != null) {
      for (final c in BillRule.columns) {
        _fields[c]!.text = r.header(c) ?? '';
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '名字不能空');
      return;
    }

    final rule = BillRule(
      name: name,
      headers: {
        for (final c in BillRule.columns)
          if (_fields[c]!.text.trim().isNotEmpty) c: _fields[c]!.text.trim(),
      },
    );
    if (!rule.isUsable) {
      final need = [for (final c in BillRule.keyColumns) BillRule.labels[c]]
          .join('、');
      setState(() => _error = '$need 这三列必须配 —— 少了它们认不出金额和方向');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final old = widget.rule;
      // 名字是主键：先改名再存，不然会变成「新增一条 + 留下旧的」
      if (old != null && old.name != name) {
        await widget.dao.renameRule(old.name, name);
      }
      await widget.dao.saveRule(rule);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().contains('UNIQUE')
              ? '已经有一条叫「$name」的了'
              : '存不住：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isNew = widget.rule == null;

    return Scaffold(
      appBar: AppBar(title: Text(isNew ? '新建解析方式' : '编辑解析方式')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名字',
              helperText: '比如「工行储蓄卡」',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('文件里的列名', style: tt.titleSmall),
          const SizedBox(height: 4),
          Text(
            '填这份文件里对应的表头名，没有的列留空。',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final c in BillRule.columns) ...[
            TextField(
              controller: _fields[c],
              decoration: InputDecoration(
                labelText: BillRule.labels[c],
                helperText:
                    '表的 $c 列${BillRule.keyColumns.contains(c) ? '，必填' : ''}',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(isNew ? '建好' : '保存修改'),
          ),
        ),
      ),
    );
  }
}
