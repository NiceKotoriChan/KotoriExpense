import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';
import '../import/mapping_rules.dart';

/// 映射规则列表：一家的账单一条规则。点进去改名、改列名。
/// 改动直接落到 settings 表，下次导入就用新的。
class CsvRulesPage extends StatefulWidget {
  final TxnDao dao;

  const CsvRulesPage({super.key, required this.dao});

  @override
  State<CsvRulesPage> createState() => _CsvRulesPageState();
}

class _CsvRulesPageState extends State<CsvRulesPage> {
  BillRules _rules = kDefaultBillRules;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.dao.csvRules();
    if (!mounted) return;
    setState(() {
      _rules = r;
      _loading = false;
    });
  }

  Future<void> _open(String ruleId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CsvRuleEditPage(dao: widget.dao, ruleId: ruleId),
      ),
    );
    await _load();
  }

  /// 新增一条空规则，然后直接进详情页取名 —— 名字在这儿问没意义，进去改更顺
  Future<void> _add() async {
    final rule = BillRule(
      id: _rules.nextId(),
      name: '新规则',
      hints: const [],
      fields: const {},
    );
    final next = _rules.upsert(rule);
    setState(() => _rules = next);
    await widget.dao.saveCsvRules(next);
    if (!mounted) return;
    await _open(rule.id);
  }

  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全部恢复默认'),
        content: const Text('你改过和加过的规则都会丢掉，回到出厂的支付宝 / 微信 / 招商银行。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.dao.resetCsvRules();
    if (!mounted) return;
    setState(() => _rules = kDefaultBillRules);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('映射规则'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _resetAll,
            icon: Icon(AppIcons.resolve('restartAlt')),
            tooltip: '全部恢复默认',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const _Note(
                  '一条规则对应一家的账单：先靠特征列认出是哪家，'
                  '再用这条规则的列名把原始文件对上数据库字段。',
                ),
                if (_rules.isEmpty)
                  const _Note(
                    '一条规则都没有，导入时谁都认不出来。往下翻加一条。',
                    isError: true,
                  ),
                for (final rule in _rules.rules)
                  _RuleTile(rule: rule, onTap: () => _open(rule.id)),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(AppIcons.resolve('addRule')),
                  title: const Text('新增一条规则'),
                  onTap: _add,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  final BillRule rule;
  final VoidCallback onTap;

  const _RuleTile({required this.rule, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final usable = rule.isUsable;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.surfaceContainerHighest,
        child: Text(
          rule.name.isEmpty ? '?' : rule.name.substring(0, 1),
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
      title: Text(rule.name),
      subtitle: Text(
        usable
            ? '${rule.mappedCount} 个字段 · 特征列 ${rule.hints.length} 个'
            : '缺交易时间 / 交易收支 / 交易金额，导入时用不了',
        style: usable
            ? null
            : tt.bodySmall?.copyWith(color: cs.error),
      ),
      trailing: Icon(AppIcons.resolve('chevronRight')),
      onTap: onTap,
    );
  }
}

/// 单条规则：改名、改特征列、改字段映射。
class CsvRuleEditPage extends StatefulWidget {
  final TxnDao dao;
  final String ruleId;

  const CsvRuleEditPage({super.key, required this.dao, required this.ruleId});

  @override
  State<CsvRuleEditPage> createState() => _CsvRuleEditPageState();
}

class _CsvRuleEditPageState extends State<CsvRuleEditPage> {
  BillRules _all = kDefaultBillRules;
  bool _loading = true;

  BillRule? get _rule => _all.byId(widget.ruleId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.dao.csvRules();
    if (!mounted) return;
    if (r.byId(widget.ruleId) == null) {
      // 规则已经不在了，别留个空壳页
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _all = r;
      _loading = false;
    });
  }

  Future<void> _save(BillRule rule) async {
    final next = _all.upsert(rule);
    setState(() => _all = next);
    await widget.dao.saveCsvRules(next);
  }

  Future<void> _rename() async {
    final rule = _rule;
    if (rule == null) return;
    final name = await editName(
      context,
      title: '规则名称',
      current: rule.name,
      hint: '比如「招商银行」「工行储蓄卡」',
    );
    if (name == null || name.isEmpty || name == rule.name) return;
    await _save(rule.copyWith(name: name));
  }

  Future<void> _editField(TxnField f) async {
    final rule = _rule;
    if (rule == null) return;
    final next = await editStringList(
      context,
      title: '${rule.name} · ${f.label}',
      current: rule.headers(f),
      hint: '这份账单里对应的列名，用逗号分隔，谁先命中用谁',
    );
    if (next == null) return;
    await _save(rule.copyWith(fields: {...rule.fields, f: next}));
  }

  Future<void> _editHints() async {
    final rule = _rule;
    if (rule == null) return;
    final next = await editStringList(
      context,
      title: '${rule.name} · 特征列',
      current: rule.hints,
      hint: '用来认出是哪家的列名，用逗号分隔',
    );
    if (next == null) return;
    await _save(rule.copyWith(hints: next));
  }

  Future<void> _restore() async {
    final rule = _rule;
    final seed = rule == null ? null : kDefaultBillRules.byId(rule.id);
    if (rule == null || seed == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认'),
        content: Text('「${rule.name}」的名称和列名都会退回出厂值「${seed.name}」。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _save(seed);
  }

  Future<void> _delete() async {
    final rule = _rule;
    if (rule == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除规则'),
        content: Text('把「${rule.name}」整条删掉？以后这种账单导入时认不出来源。'),
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
    if (ok != true) return;
    await widget.dao.saveCsvRules(_all.remove(rule.id));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final rule = _rule;
    return Scaffold(
      appBar: AppBar(
        title: Text(rule?.name ?? '规则'),
        actions: [
          IconButton(
            onPressed: rule == null ? null : _delete,
            icon: Icon(AppIcons.resolve('deleteTxn')),
            tooltip: '删除规则',
          ),
        ],
      ),
      body: _loading || rule == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (!rule.isUsable)
                  const _Note(
                    '交易时间 / 交易收支 / 交易金额 是认表头的关键，'
                    '三个都得填上列名，这条规则才能用来导入。',
                    isError: true,
                  )
                else
                  const _Note('左边是数据库字段，右边填这份账单里对应的列名。'),
                _FieldRow(
                  label: '规则名称',
                  value: rule.name,
                  onTap: _rename,
                ),
                _FieldRow(
                  label: '特征列',
                  value: rule.hints.isEmpty ? '（空，认不出来源）' : rule.hints.join('、'),
                  muted: rule.hints.isEmpty,
                  onTap: _editHints,
                ),
                const Divider(height: 1),
                for (final f in TxnField.values) ...[
                  _FieldRow(
                    label: f.label,
                    value: _fieldText(rule, f),
                    muted: rule.headers(f).isEmpty,
                    onTap: () => _editField(f),
                  ),
                  if (f != TxnField.values.last)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
                const SizedBox(height: 16),
                if (kDefaultBillRules.byId(rule.id) != null)
                  ListTile(
                    leading: Icon(AppIcons.resolve('restartAlt')),
                    title: const Text('恢复默认'),
                    subtitle: const Text('退回这条规则的出厂列名'),
                    onTap: _restore,
                  ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  String _fieldText(BillRule rule, TxnField f) {
    final headers = rule.headers(f);
    if (headers.isNotEmpty) return headers.join('、');
    // 货币没列名时会补默认值，说明一下比一个「（空）」有用
    return f == TxnField.currency ? '（留空 → $kDefaultCurrency）' : '（留空）';
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool muted;

  const _FieldRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium?.copyWith(
                  color: muted ? cs.outline : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  final bool isError;

  const _Note(this.text, {this.isError = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: isError ? cs.error : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 单行文本编辑弹窗。返回 null 表示取消，返回已 trim 的字符串。
Future<String?> editName(
  BuildContext context, {
  required String title,
  required String current,
  String? hint,
}) => _promptText(context, title: title, current: current, hint: hint);

/// 逗号分隔的字符串列表编辑弹窗。返回 null 表示取消。
Future<List<String>?> editStringList(
  BuildContext context, {
  required String title,
  required List<String> current,
  String? hint,
}) async {
  final raw = await _promptText(
    context,
    title: title,
    current: current.join('、'),
    hint: hint,
    multiline: true,
  );
  return raw == null ? null : splitList(raw);
}

Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required String current,
  String? hint,
  bool multiline = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(
    title: title,
    initial: current,
    hint: hint,
    multiline: multiline,
  ),
);

/// 输入框的 controller 要活到退场动画结束：showDialog 的 Future 在动画开始时就完成了，
/// await 完就 dispose，TextField 还在重建时会撞上
/// 「TextEditingController was used after being disposed」。
/// 交给对话框自己持有，它被真正移除时才释放。
class _TextDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String? hint;
  final bool multiline;

  const _TextDialog({
    required this.title,
    required this.initial,
    this.hint,
    this.multiline = false,
  });

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void initState() {
    super.initState();
    // 打开就把原来的字全选上，要换直接打，要留按取消
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _ctrl.text.length,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _ctrl,
      autofocus: true,
      minLines: widget.multiline ? 1 : null,
      maxLines: widget.multiline ? 4 : 1,
      decoration: InputDecoration(
        hintText: widget.hint,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (v) => Navigator.pop(context, v.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
        child: const Text('保存'),
      ),
    ],
  );
}

/// 逗号 / 顿号 / 竖线 / 换行 都能当分隔符
List<String> splitList(String s) => s
    .split(RegExp(r'[,，、|\n]'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();
