import 'package:flutter/material.dart';

import '../bill_visibility.dart';
import '../db.dart';
import '../models.dart';
import '../stats.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class YearPage extends StatefulWidget {
  final TxnDao dao;
  final BillVisibility visibility;
  final int refreshToken;

  const YearPage({
    super.key,
    required this.dao,
    required this.visibility,
    required this.refreshToken,
  });

  @override
  State<YearPage> createState() => _YearPageState();
}

class _YearPageState extends State<YearPage> {
  int _year = DateTime.now().year;
  bool _located = false;
  bool _expense = true;
  bool _loading = true;
  List<Txn> _txns = const [];
  Map<String, String> _categoryIcons = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant YearPage old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    if (!_located) {
      _located = true;
      final latest = await widget.dao.latestDate();
      if (latest != null) {
        final y = yearOf(latest);
        if (y > 0) _year = y;
      }
    }
    final txns = await widget.dao.listRange(
      isoDate(_year, 1, 1),
      isoDate(_year, 12, 31),
    );
    final icons = await widget.dao.categoryIcons();
    if (!mounted) return;
    setState(() {
      _txns = widget.visibility.visible(txns);
      _categoryIcons = icons;
      _loading = false;
    });
  }

  Future<void> _pickYear() async {
    final y = await showYearWheelPicker(context, year: _year);
    if (y == null || !mounted) return;
    setState(() {
      _year = y;
      _loading = true;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _expense ? cs.error : cs.primary;
    final filtered = byDirection(_txns, expense: _expense);
    final totals = monthlyTotals(filtered, _year);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: RangeButton(label: '$_year 年', onTap: _pickYear),
        actions: [
          DirectionToggle(
            expense: _expense,
            onChanged: (v) => setState(() => _expense = v),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  TotalRow(
                    expense: _expense,
                    cents: totalCents(filtered),
                    count: filtered.length,
                  ),
                  ChartSection(
                    title: _expense ? '每月消费对比' : '每月盈利对比',
                    child: BarChart(
                      values: totals.sublist(1),
                      labels: [for (var m = 1; m <= 12; m++) '$m'],
                      color: color,
                    ),
                  ),
                  ChartSection(
                    title: '分类占比',
                    child: PieChart(
                      slices: [
                        for (final s in collapseTail(sumByCategory(filtered)))
                          ChartSlice(s.category, s.cents),
                      ],
                    ),
                  ),
                  ChartSection(
                    title: _expense ? '消费排行 Top 10' : '盈利排行 Top 10',
                    child: RankedList(
                      items: topTxns(filtered),
                      totalCents: totalCents(filtered),
                      expense: _expense,
                      categoryIcons: _categoryIcons,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
