import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../stats.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

/// 月度：切换月 + 支出/收入切换 + 日历图 + 分类饼图 + Top 10
class MonthPage extends StatefulWidget {
  final TxnDao dao;

  /// 变了就重新读库（导入之后外壳会把它 +1）
  final int refreshToken;

  const MonthPage({super.key, required this.dao, required this.refreshToken});

  @override
  State<MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<MonthPage> {
  late int _year;
  late int _month;
  bool _expense = true;
  bool _loading = true;
  List<Txn> _txns = const [];
  Map<String, String> _categoryIcons = const {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  @override
  void didUpdateWidget(covariant MonthPage old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    final from = isoDate(_year, _month, 1);
    final to = isoDate(_year, _month, daysInMonth(_year, _month));
    final txns = await widget.dao.listRange(from, to);
    final icons = await widget.dao.categoryIcons();
    if (!mounted) return;
    setState(() {
      _txns = txns;
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
                      items: topCategories(filtered),
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
