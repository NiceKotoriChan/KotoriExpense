import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'bill_visibility.dart';
import 'db.dart';
import 'icons.dart';
import 'pages/home_page.dart';
import 'pages/month_page.dart';
import 'pages/settings_page.dart';
import 'pages/year_page.dart';
import 'update.dart';
import 'widgets/update_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final db = await openAppDb(factory: sqflite.databaseFactory);
    final dir = await sqflite.databaseFactory.getDatabasesPath();
    final visibility = await BillVisibility.open(
      File(p.join(dir, 'bill_visibility.json')),
    );
    runApp(KotoriExpenseApp(dao: TxnDao(db), visibility: visibility));
  } catch (e) {
    runApp(_DbErrorApp(message: '$e'));
  }
}

class _DbErrorApp extends StatelessWidget {
  final String message;

  const _DbErrorApp({required this.message});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText('打开数据库失败：\n\n$message'),
          ),
        ),
      ),
    ),
  );
}

class KotoriExpenseApp extends StatelessWidget {
  final TxnDao dao;
  final BillVisibility visibility;

  const KotoriExpenseApp({
    super.key,
    required this.dao,
    required this.visibility,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kotori 记账',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3F7D6E),
      ),
      home: AppShell(dao: dao, visibility: visibility),
    );
  }
}

class AppShell extends StatefulWidget {
  final TxnDao dao;
  final BillVisibility visibility;

  const AppShell({super.key, required this.dao, required this.visibility});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final PageController _controller = PageController();
  int _index = 0;
  int _refreshToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final release = await fetchLatestRelease();
      if (release.apk == null) return;
      if (!isNewerVersion(release.version, info.version)) return;

      final skipped = (await widget.dao.settings())[kSkippedUpdateKey];
      if (skipped == release.version) return;
      if (!mounted) return;

      final r = await showUpdateDialog(
        context,
        release: release,
        current: info.version,
      );
      if (r == false) {
        await widget.dao.saveSettings({kSkippedUpdateKey: release.version});
      }
    } catch (_) {
      return;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _bump() => setState(() => _refreshToken++);

  void _go(int i) {
    setState(() => _index = i);
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() => _index = i),
        children: [
          HomePage(
            dao: widget.dao,
            visibility: widget.visibility,
            refreshToken: _refreshToken,
            onDataChanged: _bump,
          ),
          MonthPage(
            dao: widget.dao,
            visibility: widget.visibility,
            refreshToken: _refreshToken,
          ),
          YearPage(
            dao: widget.dao,
            visibility: widget.visibility,
            refreshToken: _refreshToken,
          ),
          SettingsPage(
            dao: widget.dao,
            visibility: widget.visibility,
            onDataChanged: _bump,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 56,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: [
          NavigationDestination(
            icon: Icon(AppIcons.resolve('tabList')),
            label: '列表',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.resolve('tabMonth')),
            label: '月度',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.resolve('tabYear')),
            label: '年度',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.resolve('tabSettings')),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
