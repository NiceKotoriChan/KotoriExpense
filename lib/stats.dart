import 'models.dart';

/// 流水聚合。纯 Dart，不碰 Flutter，也不碰数据库 —— 页面拿到的是一整段
/// 流水，这里只负责算。个人记账数据量很小，全部在 Dart 侧算比写 SQL 好维护。

/// date 形如 'YYYY-MM-DD HH:MM:SS'，直接切字符串，不经过 DateTime
/// （免去时区/夏令时的幺蛾子）。
int yearOf(String date) =>
    date.length >= 4 ? (int.tryParse(date.substring(0, 4)) ?? 0) : 0;

int monthOf(String date) =>
    date.length >= 7 ? (int.tryParse(date.substring(5, 7)) ?? 0) : 0;

int dayOf(String date) =>
    date.length >= 10 ? (int.tryParse(date.substring(8, 10)) ?? 0) : 0;

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// 某个月一号是星期几，1 = 周一 ... 7 = 周日（跟日历列对齐）
int weekdayOfFirst(int year, int month) => DateTime(year, month, 1).weekday;

List<Txn> inMonth(Iterable<Txn> txns, int year, int month) => txns
    .where((t) => yearOf(t.date) == year && monthOf(t.date) == month)
    .toList();

List<Txn> inYear(Iterable<Txn> txns, int year) =>
    txns.where((t) => yearOf(t.date) == year).toList();

/// [expense] 为 true 取支出，否则取收入
List<Txn> byDirection(Iterable<Txn> txns, {required bool expense}) =>
    txns.where((t) => t.isExpense == expense).toList();

int totalCents(Iterable<Txn> txns) =>
    txns.fold(0, (sum, t) => sum + t.amountCents);

class CategorySum {
  /// 分类为空的一律归到「未分类」
  final String category;
  final int cents;
  final int count;

  const CategorySum({
    required this.category,
    required this.cents,
    required this.count,
  });

  static const String uncategorized = '未分类';
}

/// 按分类合计，金额从大到小
List<CategorySum> sumByCategory(Iterable<Txn> txns) {
  final cents = <String, int>{};
  final count = <String, int>{};
  for (final t in txns) {
    final key = (t.category == null || t.category!.isEmpty)
        ? CategorySum.uncategorized
        : t.category!;
    cents[key] = (cents[key] ?? 0) + t.amountCents;
    count[key] = (count[key] ?? 0) + 1;
  }
  final out = [
    for (final e in cents.entries)
      CategorySum(category: e.key, cents: e.value, count: count[e.key]!),
  ];
  out.sort((a, b) {
    final c = b.cents.compareTo(a.cents);
    return c != 0 ? c : a.category.compareTo(b.category);
  });
  return out;
}

/// 日历图用。返回长度 daysInMonth+1 的数组，下标就是日（0 位不用）。
List<int> dailyTotals(Iterable<Txn> txns, int year, int month) {
  final out = List<int>.filled(daysInMonth(year, month) + 1, 0);
  for (final t in txns) {
    final d = dayOf(t.date);
    if (d >= 1 && d < out.length) out[d] += t.amountCents;
  }
  return out;
}

/// 年度柱状图用。返回长度 13 的数组，下标就是月（0 位不用）。
List<int> monthlyTotals(Iterable<Txn> txns, int year) {
  final out = List<int>.filled(13, 0);
  for (final t in txns) {
    final m = monthOf(t.date);
    if (m >= 1 && m <= 12) out[m] += t.amountCents;
  }
  return out;
}

/// 排行前 [limit] 名。[by] 决定按什么排：默认金额，可换成笔数。
List<CategorySum> topCategories(
  Iterable<Txn> txns, {
  int limit = 10,
  bool byCount = false,
}) {
  final list = sumByCategory(txns);
  if (byCount) {
    list.sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : b.cents.compareTo(a.cents);
    });
  }
  return list.length > limit ? list.sublist(0, limit) : list;
}

/// 数据里出现过的年份，倒序；空数据时给当前年
List<int> yearsPresent(Iterable<Txn> txns) {
  final years = <int>{};
  for (final t in txns) {
    final y = yearOf(t.date);
    if (y > 0) years.add(y);
  }
  if (years.isEmpty) years.add(DateTime.now().year);
  final out = years.toList()..sort((a, b) => b.compareTo(a));
  return out;
}

const List<String> kMonthNames = [
  '',
  '1 月',
  '2 月',
  '3 月',
  '4 月',
  '5 月',
  '6 月',
  '7 月',
  '8 月',
  '9 月',
  '10 月',
  '11 月',
  '12 月',
];

/// 月份加减，返回 (year, month)
({int year, int month}) shiftMonth(int year, int month, int delta) {
  final total = year * 12 + (month - 1) + delta;
  return (year: total ~/ 12, month: total % 12 + 1);
}

String isoDate(int year, int month, int day) =>
    '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

/// 把长尾并成一条「其他 N 类」，免得饼图切成十几片看不清
List<CategorySum> collapseTail(
  List<CategorySum> sums, {
  int limit = 8,
  String label = '其他',
}) {
  if (sums.length <= limit) return sums;
  final rest = sums.skip(limit - 1).toList();
  return [
    ...sums.take(limit - 1),
    CategorySum(
      category: '$label ${rest.length} 类',
      cents: rest.fold(0, (a, s) => a + s.cents),
      count: rest.fold(0, (a, s) => a + s.count),
    ),
  ];
}

/// 同一天的流水打包在一起
class DayGroup {
  /// 'YYYY-MM-DD'
  final String date;
  final List<Txn> txns;
  final int expenseCents;
  final int incomeCents;

  const DayGroup({
    required this.date,
    required this.txns,
    required this.expenseCents,
    required this.incomeCents,
  });
}

/// 按天分组。入参需已按时间倒序（`listAll` / `listRange` / `search` 都是），
/// 这里只按日期切段，不重排。
List<DayGroup> groupByDay(Iterable<Txn> txns) {
  final order = <String>[];
  final map = <String, List<Txn>>{};
  for (final t in txns) {
    final d = t.date.length >= 10 ? t.date.substring(0, 10) : t.date;
    if (!map.containsKey(d)) {
      order.add(d);
      map[d] = <Txn>[];
    }
    map[d]!.add(t);
  }

  return [
    for (final d in order)
      DayGroup(
        date: d,
        txns: map[d]!,
        expenseCents: map[d]!
            .where((t) => t.isExpense)
            .fold(0, (a, t) => a + t.amountCents),
        incomeCents: map[d]!
            .where((t) => !t.isExpense)
            .fold(0, (a, t) => a + t.amountCents),
      ),
  ];
}

/// '2026-09-03' -> '9月3日 周三'，今天和昨天就直接说今天昨天
String dayLabel(String date, {DateTime? today}) {
  final d = DateTime.tryParse(date);
  if (d == null) return date;

  final now = today ?? DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  final base = '${d.month}月${d.day}日 周${'一二三四五六日'[d.weekday - 1]}';
  if (sameDay(d, now)) return '今天 · $base';
  if (sameDay(d, yesterday)) return '昨天 · $base';
  return base;
}
