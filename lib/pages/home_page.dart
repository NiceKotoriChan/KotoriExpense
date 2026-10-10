import 'package:flutter/material.dart';

import '../bill_visibility.dart';
import '../db.dart';
import '../icons.dart';
import '../models.dart';
import '../stats.dart';
import '../widgets/txn_list.dart';
import 'search_page.dart';
import 'txn_edit_page.dart';

class HomePage extends StatefulWidget {
  final TxnDao dao;
  final BillVisibility visibility;
  final int refreshToken;
  final VoidCallback? onDataChanged;

  const HomePage({
    super.key,
    required this.dao,
    required this.visibility,
    this.refreshToken = 0,
    this.onDataChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Txn> _txns = const [];
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
    final all = await widget.dao.listAll();
    final icons = await widget.dao.categoryIcons();
    if (!mounted) return;
    setState(() {
      _txns = widget.visibility.visible(all);
      _categoryIcons = icons;
      _loading = false;
    });
  }

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
      MaterialPageRoute(
        builder: (_) =>
            SearchPage(dao: widget.dao, visibility: widget.visibility),
      ),
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
                          _SummaryBar(txns: _txns),
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
  final List<Txn> txns;

  const _SummaryBar({required this.txns});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final expense = totalCents(byDirection(txns, expense: true));
    final income = totalCents(byDirection(txns, expense: false));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          _Metric(label: '支出', text: formatCents(expense), color: cs.error),
          _Metric(label: '收入', text: formatCents(income), color: cs.primary),
          _Metric(label: '笔数', text: '${txns.length}', color: cs.onSurface),
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
