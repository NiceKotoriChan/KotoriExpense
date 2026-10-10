import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';

class IconMappingPage extends StatefulWidget {
  final TxnDao dao;
  final VoidCallback? onChanged;

  const IconMappingPage({super.key, required this.dao, this.onChanged});

  @override
  State<IconMappingPage> createState() => _IconMappingPageState();
}

class _IconMappingPageState extends State<IconMappingPage> {
  Map<String, String> _mapping = const {};
  List<String> _categories = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await widget.dao.categoryIcons();
    final c = await widget.dao.knownCategories();
    if (!mounted) return;
    setState(() {
      _mapping = m;
      _categories = c;
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

  Future<void> _clear(String category) async {
    await widget.dao.clearCategoryIcon(category);
    widget.onChanged?.call();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final categories = _categories;

    return Scaffold(
      appBar: AppBar(title: const Text('图标映射')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : categories.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.resolve('palette'), size: 48, color: cs.outline),
                  const SizedBox(height: 12),
                  Text(
                    '还没有分类',
                    style: tt.bodyMedium?.copyWith(color: cs.outline),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: categories.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = categories[i];
                final icon = _mapping[c];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.surfaceContainerHighest,
                    child: Icon(
                      AppIcons.resolve(icon),
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  title: Text(c),
                  subtitle: icon == null ? null : Text(icon),
                  trailing: icon == null
                      ? null
                      : IconButton(
                          onPressed: () => _clear(c),
                          icon: Icon(AppIcons.resolve('restartAlt')),
                          tooltip: '清除映射',
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
