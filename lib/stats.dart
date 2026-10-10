import 'models.dart';

int yearOf(String date) =>
    date.length >= 4 ? (int.tryParse(date.substring(0, 4)) ?? 0) : 0;

int monthOf(String date) =>
    date.length >= 7 ? (int.tryParse(date.substring(5, 7)) ?? 0) : 0;

int dayOf(String date) =>
    date.length >= 10 ? (int.tryParse(date.substring(8, 10)) ?? 0) : 0;

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

List<Txn> byDirection(Iterable<Txn> txns, {required bool expense}) =>
    txns.where((t) => t.isExpense == expense).toList();

int totalCents(Iterable<Txn> txns) =>
    txns.fold(0, (sum, t) => sum + t.amountCents);

class CategorySum {
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

List<int> dailyTotals(Iterable<Txn> txns, int year, int month) {
  final out = List<int>.filled(daysInMonth(year, month) + 1, 0);
  for (final t in txns) {
    final d = dayOf(t.date);
    if (d >= 1 && d < out.length) out[d] += t.amountCents;
  }
  return out;
}

List<int> monthlyTotals(Iterable<Txn> txns, int year) {
  final out = List<int>.filled(13, 0);
  for (final t in txns) {
    final m = monthOf(t.date);
    if (m >= 1 && m <= 12) out[m] += t.amountCents;
  }
  return out;
}

List<Txn> topTxns(Iterable<Txn> txns, {int limit = 10}) {
  final list = txns.toList();
  list.sort((a, b) {
    final cents = b.amountCents.compareTo(a.amountCents);
    if (cents != 0) return cents;
    final date = b.date.compareTo(a.date);
    if (date != 0) return date;
    return (b.id ?? '').compareTo(a.id ?? '');
  });
  return list.length > limit ? list.sublist(0, limit) : list;
}

String isoDate(int year, int month, int day) =>
    '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

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

class DayGroup {
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
