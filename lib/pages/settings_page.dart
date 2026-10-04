import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';
import 'bill_rules_page.dart';
import 'icon_mapping_page.dart';
import 'import_page.dart';

class SettingsPage extends StatefulWidget {
  final TxnDao dao;
  final int refreshToken;

  /// 导入或改配置之后叫外壳刷新其他页
  final VoidCallback? onDataChanged;

  const SettingsPage({
    super.key,
    required this.dao,
    required this.refreshToken,
    this.onDataChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SettingsPage old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    final n = await widget.dao.count();
    if (mounted) setState(() => _count = n);
  }

  Future<void> _openImport() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ImportPage(dao: widget.dao)),
    );
    if (changed == true) {
      widget.onDataChanged?.call();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          children: [
            ListTile(
              leading: Icon(AppIcons.resolve('importBill')),
              title: const Text('导入账单'),
              subtitle: const Text('CSV / TSV / XLSX'),
              trailing: Icon(AppIcons.resolve('chevronRight')),
              onTap: _openImport,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(AppIcons.resolve('tableChart')),
              title: const Text('解析方式'),
              subtitle: const Text('把文件里的列名对应到表的列名'),
              trailing: Icon(AppIcons.resolve('chevronRight')),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BillRulesPage(dao: widget.dao),
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(AppIcons.resolve('palette')),
              title: const Text('渲染 ICON 与分类映射'),
              subtitle: const Text('每个分类用哪个图标'),
              trailing: Icon(AppIcons.resolve('chevronRight')),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => IconMappingPage(
                      dao: widget.dao,
                      onChanged: widget.onDataChanged,
                    ),
                  ),
                );
                await _load();
              },
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '库里现有 $_count 条流水',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
