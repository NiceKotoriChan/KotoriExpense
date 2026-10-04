import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';

/// 分类 -> 图标。改动直接落到 category_icon 表。
class IconMappingPage extends StatefulWidget {
  final TxnDao dao;

  /// 有什么改动时通知外壳（列表页的图标要跟着变）
  final VoidCallback? onChanged;

  const IconMappingPage({super.key, required this.dao, this.onChanged});

  @override
  State<IconMappingPage> createState() => _IconMappingPageState();
}

class _IconMappingPageState extends State<IconMappingPage> {
  Map<String, String> _mapping = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await widget.dao.categoryIcons();
    if (!mounted) return;
    setState(() {
      _mapping = m;
      _loading = false;
    });
  }

  Future<void> _pick(String category) async {
    final picked = await _showIconPicker(context, _mapping[category]);
    if (picked == null) return;
    await widget.dao.setCategoryIcon(category, picked);
    widget.onChanged?.call();
    await _load();
  }

  Future<void> _reset(String category) async {
    await widget.dao.resetCategoryIcon(category);
    widget.onChanged?.call();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _mapping.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('分类图标')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: categories.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = categories[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: Icon(
                      AppIcons.resolve(_mapping[c]),
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: Text(c),
                  subtitle: Text(_mapping[c] ?? ''),
                  trailing: IconButton(
                    onPressed: () => _reset(c),
                    icon: Icon(AppIcons.resolve('restartAlt')),
                    tooltip: '恢复默认',
                  ),
                  onTap: () => _pick(c),
                );
              },
            ),
    );
  }
}

Future<String?> _showIconPicker(BuildContext context, String? current) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      builder: (ctx, scroll) {
        final cs = Theme.of(ctx).colorScheme;
        final names = AppIcons.categoryIconNames;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text('选个图标', style: Theme.of(ctx).textTheme.titleMedium),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 72,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: names.length,
                itemBuilder: (_, i) {
                  final name = names[i];
                  final selected = name == current;
                  // 用 Material 垫底而不是 DecoratedBox —— 后者画在墨水层之上，
                  // 点下去的水波纹会被颜色盖住看不见。
                  return Material(
                    color: selected ? cs.primaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, name),
                      child: Center(
                        child: Icon(
                          AppIcons.resolve(name),
                          color: selected
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
