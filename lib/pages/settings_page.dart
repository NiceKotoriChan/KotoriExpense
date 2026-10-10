import 'package:flutter/material.dart';

import '../bill_visibility.dart';
import '../db.dart';
import '../icons.dart';
import 'ai_config_page.dart';
import 'auto_category_page.dart';
import 'icon_mapping_page.dart';
import 'import_page.dart';
import 'records_page.dart';

class SettingsPage extends StatelessWidget {
  final TxnDao dao;
  final BillVisibility visibility;
  final VoidCallback? onDataChanged;

  const SettingsPage({
    super.key,
    required this.dao,
    required this.visibility,
    this.onDataChanged,
  });

  Future<void> _openImport(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ImportPage(dao: dao)),
    );
    if (changed == true) onDataChanged?.call();
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final entries = <({String icon, String title, VoidCallback onTap})>[
      (
        icon: 'importBill',
        title: '导入账单',
        onTap: () => _openImport(context),
      ),
      (
        icon: 'importRecords',
        title: '管理账单',
        onTap: () => _push(
          context,
          RecordsPage(
            dao: dao,
            visibility: visibility,
            onDataChanged: onDataChanged,
          ),
        ),
      ),
      (
        icon: 'autoCategory',
        title: '自动分类',
        onTap: () => _push(
          context,
          AutoCategoryPage(dao: dao, onDataChanged: onDataChanged),
        ),
      ),
      (
        icon: 'palette',
        title: '图标映射',
        onTap: () =>
            _push(context, IconMappingPage(dao: dao, onChanged: onDataChanged)),
      ),
      (
        icon: 'aiConfig',
        title: '模型配置',
        onTap: () => _push(context, AiConfigPage(dao: dao)),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                leading: Icon(AppIcons.resolve(entries[i].icon)),
                title: Text(entries[i].title),
                trailing: Icon(AppIcons.resolve('chevronRight')),
                onTap: entries[i].onTap,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
