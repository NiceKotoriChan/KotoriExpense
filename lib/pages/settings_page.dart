import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../bill_visibility.dart';
import '../db.dart';
import '../icons.dart';
import '../update.dart';
import '../widgets/update_dialog.dart';
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
            const Divider(height: 1),
            _UpdateTile(dao: dao),
          ],
        ),
      ),
    );
  }
}

class _UpdateTile extends StatefulWidget {
  final TxnDao dao;

  const _UpdateTile({required this.dao});

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  String? _version;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      return;
    }
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final info = await PackageInfo.fromPlatform();
      final release = await fetchLatestRelease();
      if (!mounted) return;

      if (!isNewerVersion(release.version, info.version)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已是最新版本 v${info.version}')),
        );
        return;
      }

      if (!Platform.isAndroid || release.apk == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('有新版本 v${release.version}：$kReleasesPage')),
        );
        return;
      }

      final r = await showUpdateDialog(
        context,
        release: release,
        current: info.version,
      );
      if (r == false) {
        await widget.dao.saveSettings({kSkippedUpdateKey: release.version});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('检查更新失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = _version;
    return ListTile(
      leading: Icon(AppIcons.resolve('update')),
      title: const Text('检查更新'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (version != null) Text('v$version'),
          const SizedBox(width: 8),
          Icon(AppIcons.resolve('chevronRight')),
        ],
      ),
      onTap: _busy ? null : _check,
    );
  }
}
