import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/models.dart';
import 'package:kotori_expense/stats.dart';

Txn _t(String date, int cents, {String dir = 'expense', String? cat}) =>
    Txn(date: date, direction: dir, amountCents: cents, category: cat);

final _all = [
  _t('2026-09-03 08:30:12', 1000, cat: '餐饮美食'),
  _t('2026-09-03 12:00:00', 2000, cat: '餐饮美食'),
  _t('2026-09-15 09:00:00', 500, cat: '交通出行'),
  _t('2026-09-20 09:00:00', 5000, dir: 'income', cat: '红包'),
  _t('2026-10-01 09:00:00', 700),
  _t('2025-12-31 23:59:59', 300, cat: '交通出行'),
];

void main() {
  group('日期切片', () {
    test('从字符串里取年月日', () {
      expect(yearOf('2026-09-03 08:30:12'), 2026);
      expect(monthOf('2026-09-03 08:30:12'), 9);
      expect(dayOf('2026-09-03 08:30:12'), 3);
      expect(yearOf(''), 0);
    });

    test('按月 / 按年筛', () {
      expect(inMonth(_all, 2026, 9), hasLength(4));
      expect(inMonth(_all, 2026, 8), isEmpty);
      expect(inYear(_all, 2026), hasLength(5));
      expect(inYear(_all, 2025), hasLength(1));
    });

    test('按方向筛', () {
      expect(byDirection(_all, expense: true), hasLength(5));
      expect(byDirection(_all, expense: false), hasLength(1));
    });

    test('月份加减跨年', () {
      expect(shiftMonth(2026, 12, 1), (year: 2027, month: 1));
      expect(shiftMonth(2026, 1, -1), (year: 2025, month: 12));
      expect(shiftMonth(2026, 9, -9), (year: 2025, month: 12));
    });

    test('每月天数（含闰年）', () {
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2026, 9), 30);
      expect(weekdayOfFirst(2026, 9), inInclusiveRange(1, 7));
    });

    test('isoDate 补零', () {
      expect(isoDate(2026, 9, 3), '2026-09-03');
      expect(isoDate(2026, 12, 31), '2026-12-31');
    });
  });

  group('聚合', () {
    test('合计', () {
      expect(totalCents(byDirection(_all, expense: true)), 4500);
      expect(totalCents(const <Txn>[]), 0);
    });

    test('日历图：按日合计', () {
      final d = dailyTotals(
        byDirection(inMonth(_all, 2026, 9), expense: true),
        2026,
        9,
      );
      expect(d, hasLength(31));
      expect(d[3], 3000);
      expect(d[15], 500);
      expect(d[1], 0);
    });

    test('柱状图：按月合计', () {
      final m = monthlyTotals(
        byDirection(inYear(_all, 2026), expense: true),
        2026,
      );
      expect(m, hasLength(13));
      expect(m[9], 3500);
      expect(m[10], 700);
      expect(m[1], 0);
    });

    test('按分类合计并倒序，空的归「未分类」', () {
      final sums = sumByCategory(
        byDirection(inYear(_all, 2026), expense: true),
      );
      expect(sums.map((s) => s.category).toList(), ['餐饮美食', '未分类', '交通出行']);
      expect(sums.first.cents, 3000);
      expect(sums.first.count, 2);
      expect(sums[1].cents, 700);
    });

    test('收入方向单独聚合', () {
      final sums = sumByCategory(
        byDirection(inYear(_all, 2026), expense: false),
      );
      expect(sums, hasLength(1));
      expect(sums.single.category, '红包');
      expect(sums.single.cents, 5000);
    });

    test('排行取前 N', () {
      final top = topCategories(
        byDirection(inYear(_all, 2026), expense: true),
        limit: 2,
      );
      expect(top, hasLength(2));
      expect(top.first.category, '餐饮美食');
    });

    test('长尾并成一条', () {
      final sums = [
        for (var i = 10; i >= 1; i--)
          CategorySum(category: 'c$i', cents: i * 100, count: 1),
      ];
      final merged = collapseTail(sums, limit: 8);
      expect(merged, hasLength(8));
      expect(merged.last.category, '其他 3 类');
      expect(merged.last.cents, 300 + 200 + 100);
      expect(merged.last.count, 3);
      // 本来就短的话原样返回
      expect(collapseTail(sums, limit: 20), hasLength(10));
    });

    test('数据里出现过的年份倒序', () {
      expect(yearsPresent(_all), [2026, 2025]);
      expect(yearsPresent(const []), [DateTime.now().year]);
    });
  });

  group('按天分组', () {
    final sorted = [..._all]..sort((a, b) => b.date.compareTo(a.date));

    test('同一天归到一起，保持时间倒序', () {
      final groups = groupByDay(sorted);
      expect(groups.map((g) => g.date).toList(), [
        '2026-10-01',
        '2026-09-20',
        '2026-09-15',
        '2026-09-03',
        '2025-12-31',
      ]);
      final sep3 = groups.firstWhere((g) => g.date == '2026-09-03');
      expect(sep3.txns, hasLength(2));
    });

    test('每天的进出合计分开算', () {
      final groups = groupByDay(sorted);
      final sep3 = groups.firstWhere((g) => g.date == '2026-09-03');
      expect(sep3.expenseCents, 3000);
      expect(sep3.incomeCents, 0);

      final sep20 = groups.firstWhere((g) => g.date == '2026-09-20');
      expect(sep20.expenseCents, 0);
      expect(sep20.incomeCents, 5000);
    });

    test('空数据给空列表', () {
      expect(groupByDay(const []), isEmpty);
    });

    test('日期标签', () {
      const names = ['一', '二', '三', '四', '五', '六', '日'];
      for (final s in ['2024-01-01', '2024-01-07', '2026-09-03']) {
        final d = DateTime.parse(s);
        expect(
          dayLabel(s, today: DateTime(2020, 6, 1)),
          endsWith('周${names[d.weekday - 1]}'),
        );
      }
    });

    test('今天 / 昨天直接说人话', () {
      final today = DateTime(2026, 10, 4);
      expect(dayLabel('2026-10-04', today: today), startsWith('今天 · '));
      expect(dayLabel('2026-10-03', today: today), startsWith('昨天 · '));
      expect(dayLabel('2026-10-02', today: today), isNot(startsWith('今天')));
      expect(dayLabel('2026-10-02', today: today), isNot(startsWith('昨天')));
    });

    test('认不出的日期原样返回', () {
      expect(dayLabel('乱七八糟'), '乱七八糟');
    });
  });
}
