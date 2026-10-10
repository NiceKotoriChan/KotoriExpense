import 'package:flutter/material.dart';

import '../bill_visibility.dart';
import '../db.dart';
import '../models.dart';
import '../stats.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class MonthPage extends StatefulWidget {
  final TxnDao dao;
  final BillVisibility visibility;
  final int refreshToken;

  const MonthPage({
    super.key,
    required this.dao,
    required this.visibility,
    required this.refreshToken,
  });

  @override
  State<MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<MonthPage> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
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
  void didUpdateWidget(covariant MonthPage old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    if (!_located) {
      _located = true;
      final latest = await widget.dao.latestDate();
      if (latest != null) {
        final y = yearOf(latest);
        final m = monthOf(latest);
        if (y > 0) _year = y;
        if (m >= 1 && m <= 12) _month = m;
      }
    }
    final from = isoDate(_year, _month, 1);
    final to = isoDate(_year, _month, daysInMonth(_year, _month));
    final txns = await widget.dao.listRange(from, to);
    final icons = await widget.dao.categoryIcons();
    if (!mounted) return;
    setState(() {
      _txns = widget.visibility.visible(txns);
      _categoryIcons = icons;
      _loading = false;
    });
  }

  Future<void> _pickMonth() async {
    final r = await showMonthWheelPicker(context, year: _year, month: _month);
    if (r == null || !mounted) return;
    setState(() {
      _year = r.year;
      _month = r.month;
      _loading = true;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _expense ? cs.error : cs.primary;
    final filtered = byDirection(_txns, expense: _expense);
    final byCategory = sumByCategory(filtered);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: RangeButton(label: '$_year 年 $_month 月', onTap: _pickMonth),
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
                    title: _expense ? '每日消费' : '每日盈利',
                    child: CalendarHeatmap(
                      year: _year,
                      month: _month,
                      dailyTotals: dailyTotals(filtered, _year, _month),
                      color: color,
                    ),
                  ),
                  ChartSection(
                    title: '分类占比',
                    child: PieChart(
                      slices: [
                        for (final s in collapseTail(byCategory))
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
