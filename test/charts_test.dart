import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/models.dart';
import 'package:kotori_expense/stats.dart';
import 'package:kotori_expense/widgets/charts.dart';
import 'package:kotori_expense/widgets/common.dart';

/// 本机跑不了 App，靠这层测试兜住布局炸掉的情况。
/// 窄屏（320 宽）也过一遍 —— 手机上很容易 overflow。
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 380,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  final slices = [
    const ChartSlice('餐饮美食', 3000),
    const ChartSlice('交通出行', 1200),
    const ChartSlice('未分类', 700),
  ];

  testWidgets('饼图能画出来（含窄屏）', (tester) async {
    await _pump(tester, PieChart(slices: slices));
    await _pump(tester, PieChart(slices: slices), width: 320);
    expect(find.text('33.3%'), findsNothing); // 3000/4900 = 61.2%
    expect(find.text('61.2%'), findsOneWidget);
  });

  testWidgets('饼图数据全零时给占位，不崩', (tester) async {
    await _pump(tester, const PieChart(slices: [ChartSlice('空', 0)]));
    expect(find.byType(ChartEmpty), findsOneWidget);
  });

  testWidgets('柱状图能画出来（含 12 根柱子与零值）', (tester) async {
    final values = List<int>.generate(12, (i) => i == 3 ? 5000 : i * 100);
    await _pump(
      tester,
      BarChart(
        values: values,
        labels: [for (var m = 1; m <= 12; m++) '$m'],
        color: Colors.red,
      ),
    );
    expect(find.text('最高 ¥50.00'), findsOneWidget);
  });

  testWidgets('柱状图全零时给占位', (tester) async {
    await _pump(
      tester,
      BarChart(
        values: List<int>.filled(12, 0),
        labels: const [],
        color: Colors.red,
      ),
    );
    expect(find.byType(ChartEmpty), findsOneWidget);
  });

  testWidgets('日历热力图：任意月起头都对得上，不留负数格', (tester) async {
    for (final month in [1, 2, 9, 12]) {
      await _pump(
        tester,
        CalendarHeatmap(
          year: 2026,
          month: month,
          dailyTotals: dailyTotals(
            [
              Txn(
                date: isoDate(2026, month, 2),
                direction: 'expense',
                amountCents: 100,
                category: '餐饮',
              ),
            ],
            2026,
            month,
          ),
          color: Colors.red,
        ),
      );
    }
    expect(find.text('单日最高 ¥1.00'), findsWidgets);
  });

  testWidgets('排行列表能画出来（长分类名要截断）', (tester) async {
    final items = [
      const CategorySum(category: '一个特别特别长的分类名字用来试截断', cents: 900, count: 3),
      const CategorySum(category: '交通出行', cents: 100, count: 1),
    ];
    await _pump(
      tester,
      RankedList(items: items, totalCents: 1000, expense: true),
      width: 320,
    );
    expect(find.text('交通出行'), findsOneWidget);
  });

  testWidgets('排行列表空数据不报错', (tester) async {
    await _pump(
      tester,
      const RankedList(items: [], totalCents: 0, expense: false),
    );
  });

  testWidgets('顶部时间按钮与视图开关能画出来', (tester) async {
    await _pump(
      tester,
      Column(
        children: [
          RangeButton(label: '2026 年 9 月', onTap: () {}),
          DirectionToggle(expense: true, onChanged: (_) {}),
          const TotalRow(expense: true, cents: 123456, count: 42),
        ],
      ),
    );
    expect(find.text('2026 年 9 月'), findsOneWidget);
    // 两个文字按钮：支出 / 收入
    expect(find.widgetWithText(TextButton, '支出'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '收入'), findsOneWidget);
    expect(find.text('¥1,234.56'), findsOneWidget);
    expect(find.text('42 笔'), findsOneWidget);
  });
}
