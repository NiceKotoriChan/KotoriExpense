import 'package:flutter/material.dart';

import '../auto_category.dart';
import '../db.dart';
import '../icons.dart';

class AutoCategoryPage extends StatefulWidget {
  final TxnDao dao;
  final VoidCallback? onDataChanged;

  const AutoCategoryPage({super.key, required this.dao, this.onDataChanged});

  @override
  State<AutoCategoryPage> createState() => _AutoCategoryPageState();
}

class _AutoCategoryPageState extends State<AutoCategoryPage> {
  List<CategoryRule>? _rules;
  Map<String, String> _icons = const {};
  List<String> _categories = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await widget.dao.categoryRules();
    final icons = await widget.dao.categoryIcons();
    final categories = await widget.dao.knownCategories();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _icons = icons;
      _categories = categories;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit([int? index]) async {
    final rules = [...?_rules];
    final rule = index == null ? null : rules[index];
    final next = await showDialog<CategoryRule>(
      context: context,
      builder: (_) => _RuleDialog(
        rule: rule,
        categories: _categories,
        icons: _icons,
      ),
    );
    if (next == null || !mounted) return;

    if (index == null) {
      rules.add(next);
    } else {
      rules[index] = next;
    }
    if (rules.where((r) => r.keyword == next.keyword).length > 1) {
      _toast('已经有「${next.keyword}」这条规则了');
      return;
    }

    await widget.dao.saveCategoryRules(rules);
    if (!mounted) return;
    await _load();
  }

  Future<void> _delete(int index) async {
    final rules = [...?_rules]..removeAt(index);
    await widget.dao.saveCategoryRules(rules);
    if (!mounted) return;
    await _load();
  }

  Future<void> _recategorize() async {
    final rules = await widget.dao.categoryRules();
    if (rules.isEmpty) {
      if (mounted) _toast('还没有规则，先加一条');
      return;
    }

    final pending = await widget.dao.uncategorized();
    final filled = [
      for (final t in applyRules(pending, rules))
        if (t.category != null && t.category!.trim().isNotEmpty) t,
    ];
    final n = await widget.dao.updateAll(filled);
    if (!mounted) return;
    _toast(n == 0 ? '没有能归类的流水' : '归类了 $n 条');
    widget.onDataChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rules = _rules;

    return Scaffold(
      appBar: AppBar(
        title: const Text('自动分类'),
        actions: [
          IconButton(
            onPressed: _recategorize,
            icon: Icon(AppIcons.resolve('recategorize')),
            tooltip: '按规则重新归类未分类的流水',
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addRule',
        onPressed: () => _edit(),
        icon: Icon(AppIcons.resolve('addRule')),
        label: const Text('加规则'),
      ),
      body: rules == null
          ? const Center(child: CircularProgressIndicator())
          : rules.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.resolve('autoCategory'), size: 48, color: cs.outline),
                  const SizedBox(height: 12),
                  Text(
                    '还没有规则',
                    style: tt.bodyMedium?.copyWith(color: cs.outline),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: rules.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                leading: CircleAvatar(
                  backgroundColor: cs.surfaceContainerHighest,
                  child: Icon(
                    AppIcons.resolve(
                      iconNameForCategory(rules[i].category, _icons),
                    ),
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                title: Text(
                  rules[i].keyword,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyLarge,
                ),
                subtitle: Text(
                  rules[i].category,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: IconButton(
                  onPressed: () => _delete(i),
                  icon: Icon(
                    AppIcons.resolve('deleteTxn'),
                    color: cs.onSurfaceVariant,
                  ),
                  tooltip: '删除',
                ),
                onLongPress: () => _edit(i),
              ),
            ),
    );
  }
}

class _RuleDialog extends StatefulWidget {
  final CategoryRule? rule;
  final List<String> categories;
  final Map<String, String> icons;

  const _RuleDialog({
    this.rule,
    required this.categories,
    required this.icons,
  });

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final TextEditingController _keyword = TextEditingController(
    text: widget.rule?.keyword ?? '',
  );
  late final TextEditingController _category = TextEditingController(
    text: widget.rule?.category ?? '',
  );

  @override
  void initState() {
    super.initState();
    _keyword.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _keyword.text.length,
    );
  }

  @override
  void dispose() {
    _keyword.dispose();
    _category.dispose();
    super.dispose();
  }

  bool get _ready =>
      _keyword.text.trim().isNotEmpty && _category.text.trim().isNotEmpty;

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final c in widget.categories)
            ListTile(
              leading: Icon(
                AppIcons.resolve(iconNameForCategory(c, widget.icons)),
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

  void _submit() {
    if (!_ready) return;
    Navigator.pop(
      context,
      CategoryRule(
        keyword: _keyword.text.trim(),
        category: _category.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rule == null ? '加一条规则' : '改这条规则'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _keyword,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '关键词',
              hintText: '比如 拼多多',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _category,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '分类',
              hintText: '比如 购物',
              border: const OutlineInputBorder(),
              suffixIcon: widget.categories.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _pickCategory,
                      icon: Icon(AppIcons.resolve('arrowDropDown')),
                      tooltip: '从已有分类里选',
                    ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _ready ? _submit : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
