import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';
import '../models.dart';
import '../widgets/txn_list.dart';
import 'search_page.dart';
import 'txn_edit_page.dart';

/// 流水列表 + 收支汇总
class HomePage extends StatefulWidget {
  final TxnDao dao;
  final int refreshToken;
  final VoidCallback? onDataChanged;

  const HomePage({
    super.key,
    required this.dao,
    this.refreshToken = 0,
    this.onDataChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Txn> _txns = const [];
  Summary _summary = const Summary(incomeCents: 0, expenseCents: 0, count: 0);
  Map<String, String> _categoryIcons = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant HomePage old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _reload();
  }

  Future<void> _reload() async {
    final txns = await widget.dao.listAll();
    final sum = await widget.dao.summary();
    final icons = await widget.dao.categoryIcons();
    if (!mounted) return;
    setState(() {
      _txns = txns;
      _summary = sum;
      _categoryIcons = icons;
      _loading = false;
    });
  }

  /// [txn] 为空就是记账，否则打开详情
  Future<void> _openEditor([Txn? txn]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TxnEditPage(dao: widget.dao, txn: txn),
      ),
    );
    if (changed == true) {
      widget.onDataChanged?.call();
      await _reload();
    }
  }

  Future<void> _openSearch() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SearchPage(dao: widget.dao)),
    );
    if (changed == true) {
      widget.onDataChanged?.call();
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RefreshIndicator(
                      onRefresh: _reload,
                      child: Column(
                        children: [
                          _SummaryBar(summary: _summary),
                          Expanded(
                            child: _txns.isEmpty
                                ? const _EmptyHint()
                                : TxnDayList(
                                    txns: _txns,
                                    categoryIcons: _categoryIcons,
                                    onTap: _openEditor,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 搜索放左下角，跟右下角的记账对称。
                  // 不走 Scaffold 的 FAB 槽：那里一个槽位放两个按钮要自己算位置，
                  // 直接贴在 body 上更确定（bottom 16 与标准 FAB 的下边距一致）。
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: FloatingActionButton(
                      heroTag: 'search',
                      onPressed: _openSearch,
                      tooltip: '搜索',
                      child: Icon(AppIcons.resolve('search')),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'record',
        onPressed: () => _openEditor(),
        icon: Icon(AppIcons.resolve('addTxn')),
        label: const Text('记账'),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final Summary summary;

  const _SummaryBar({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          _Metric(
            label: '支出',
            text: formatCents(summary.expenseCents),
            color: cs.error,
          ),
          _Metric(
            label: '收入',
            text: formatCents(summary.incomeCents),
            color: cs.primary,
          ),
          _Metric(label: '笔数', text: '${summary.count}', color: cs.onSurface),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String text;
  final Color color;

  const _Metric({required this.label, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(label, style: tt.labelMedium),
          const SizedBox(height: 6),
          Text(
            text,
            style: tt.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppIcons.resolve('emptyState'),
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text('还没有流水，点右下角记一笔'),
        ],
      ),
    );
  }
}
