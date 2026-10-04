import 'package:flutter/cupertino.dart'
    show CupertinoPickerDefaultSelectionOverlay;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/icons.dart';
import 'package:kotori_expense/main.dart';
import 'package:kotori_expense/models.dart';
import 'package:kotori_expense/stats.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 底部导航只有图标（labelBehavior 是 alwaysHide），所以按图标点。
Future<void> _tapTab(WidgetTester tester, String icon) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(AppIcons.resolve(icon)),
    ),
  );
}

void main() {
  sqfliteFfiInit();

  testWidgets('外壳：四页都能起来，切页不报布局异常', (tester) async {
    setView(tester);

    // 数据挂在「当前月」，免得测试结果跟着跑的日子变
    final now = DateTime.now();
    final thisMonth = isoDate(now.year, now.month, 5);

    final dao = await openTempDb(tester);
    await dbCall(
      tester,
      () => dao.insertAll([
        Txn(
          date: '$thisMonth 08:30:12',
          direction: 'expense',
          amountCents: 1900,
          counterparty: '瑞幸咖啡',
          category: '餐饮美食',
          type: '余额宝',
        ),
        Txn(
          date: '$thisMonth 12:00:00',
          direction: 'expense',
          amountCents: 3250,
          counterparty: '美团',
          category: '餐饮美食',
        ),
        Txn(
          date: '$thisMonth 19:00:00',
          direction: 'income',
          amountCents: 20000,
          counterparty: '张三',
          category: '红包',
        ),
      ]),
    );

    await tester.pumpWidget(MaterialApp(home: AppShell(dao: dao)));
    await settle(tester);

    // 底部导航：只有图标，没有文字，且比默认的 80 矮
    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.labelBehavior, NavigationDestinationLabelBehavior.alwaysHide);
    expect(tester.getSize(find.byType(NavigationBar)).height, 56);
    for (final icon in ['tabList', 'tabMonth', 'tabYear', 'tabSettings']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(AppIcons.resolve(icon)),
        ),
        findsOneWidget,
        reason: '底部导航缺少「$icon」',
      );
    }
    expect(tester.takeException(), isNull);

    await _tapTab(tester, 'tabMonth');
    await settle(tester);
    expect(find.text('每日消费'), findsOneWidget);
    expect(find.text('分类占比'), findsWidgets);
    expect(find.text('消费排行 Top 10'), findsOneWidget);

    // 月度页右上角两个文字按钮，点「收入」切到收入视图
    await tester.tap(
      find.descendant(of: find.byType(AppBar), matching: find.text('收入')),
    );
    await settle(tester);
    expect(find.text('每日盈利'), findsOneWidget);
    expect(find.text('盈利排行 Top 10'), findsOneWidget);

    await _tapTab(tester, 'tabYear');
    await settle(tester);
    expect(find.text('每月消费对比'), findsOneWidget);
    expect(find.text('消费排行 Top 10'), findsOneWidget);

    await _tapTab(tester, 'tabSettings');
    await settle(tester);
    expect(find.text('导入账单'), findsOneWidget);
    expect(find.text('映射规则'), findsOneWidget);
    expect(find.text('渲染 ICON 与分类映射'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('列表页：搜索在左、记账在右，流水按天分组', (tester) async {
    setView(tester, width: 400, height: 900);
    final dao = await openTempDb(tester);

    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    await dbCall(
      tester,
      () => dao.insertAll([
        Txn(
          date: '${isoDate(now.year, now.month, now.day)} 10:00:00',
          direction: 'expense',
          amountCents: 1900,
          counterparty: '今天的店',
          category: '餐饮美食',
        ),
        Txn(
          date: '${isoDate(now.year, now.month, now.day)} 12:00:00',
          direction: 'expense',
          amountCents: 3250,
          counterparty: '今天另一家',
          category: '餐饮美食',
        ),
        Txn(
          date:
              '${isoDate(yesterday.year, yesterday.month, yesterday.day)} 19:00:00',
          direction: 'expense',
          amountCents: 800,
          counterparty: '昨天的店',
          category: '交通出行',
        ),
      ]),
    );

    await tester.pumpWidget(MaterialApp(home: AppShell(dao: dao)));
    await settle(tester);

    // 两个按钮一个贴左一个贴右，别跑到屏幕外面去
    const width = 400.0;
    final searchFab = tester.getRect(
      find.ancestor(
        of: find.byIcon(AppIcons.resolve('search')),
        matching: find.byType(FloatingActionButton),
      ),
    );
    final recordFab = tester.getRect(
      find.widgetWithText(FloatingActionButton, '记账'),
    );
    expect(searchFab.left, closeTo(16, 2), reason: '搜索该贴在左边');
    expect(recordFab.right, closeTo(width - 16, 2), reason: '记账该贴在右边');
    expect(searchFab.center.dx, lessThan(width / 2));
    expect(searchFab.bottom, closeTo(recordFab.bottom, 2), reason: '两个按钮同一条底线');

    // 按天分组：今天 / 昨天各一条分隔
    expect(find.textContaining('今天 · '), findsOneWidget);
    expect(find.textContaining('昨天 · '), findsOneWidget);
    // 今天的支出合计 19.00 + 32.50 = 51.50
    expect(find.text('支出 ¥51.50'), findsOneWidget);
    expect(find.text('支出 ¥8.00'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页能进二级页：映射规则与分类图标', (tester) async {
    setView(tester);

    final dao = await openTempDb(tester);

    await tester.pumpWidget(MaterialApp(home: AppShell(dao: dao)));
    await settle(tester);
    await _tapTab(tester, 'tabSettings');
    await settle(tester);

    await tester.tap(find.text('映射规则'));
    await settle(tester);
    // 列表页：一家一条规则
    expect(find.text('支付宝'), findsOneWidget);
    expect(find.text('微信'), findsOneWidget);
    expect(find.text('招商银行'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 点进一条才是字段映射
    await tester.tap(find.text('支付宝'));
    await settle(tester);
    expect(find.text('特征列'), findsOneWidget);
    expect(find.text('交易货币'), findsOneWidget);
    expect(find.text('交易收支'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pageBack(); // 回列表
    await settle(tester);
    await tester.pageBack(); // 回设置
    await settle(tester);

    await tester.tap(find.text('渲染 ICON 与分类映射'));
    await settle(tester);
    expect(find.text('分类图标'), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets);
    expect(tester.takeException(), isNull);

    // 点一个分类，图标选择器要能弹出来
    await tester.tap(find.byType(ListTile).first);
    await settle(tester);
    expect(find.text('选个图标'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('月度页：左上角时间切换弹滚轮选月份', (tester) async {
    setView(tester, width: 400, height: 900);

    final now = DateTime.now();
    final dao = await openTempDb(tester);
    await dbCall(
      tester,
      () => dao.insert(
        Txn(
          date: '${isoDate(now.year, now.month, now.day)} 10:00:00',
          direction: 'expense',
          amountCents: 1900,
          category: '餐饮美食',
        ),
      ),
    );

    await tester.pumpWidget(MaterialApp(home: AppShell(dao: dao)));
    await settle(tester);
    await _tapTab(tester, 'tabMonth');
    await settle(tester);

    await tester.tap(find.text('${now.year} 年 ${now.month} 月'));
    await settle(tester);
    // 左边年、右边月，两个滚轮
    expect(find.byType(ListWheelScrollView), findsNWidgets(2));
    expect(find.text('${now.year} 年'), findsOneWidget);
    // 选中底色得是库自带的半透明层：自己糊一层不透明的，中间那行就被盖住了
    expect(
      find.byType(CupertinoPickerDefaultSelectionOverlay),
      findsNWidgets(2),
    );

    // 年轮往上滚一格 = 下一年
    await tester.drag(
      find.byType(ListWheelScrollView).first,
      const Offset(0, -50),
    );
    await settle(tester);
    await tester.tap(find.text('确定'));
    await settle(tester);

    expect(find.byType(ListWheelScrollView), findsNothing, reason: '确定之后该关框');
    expect(find.text('${now.year + 1} 年 ${now.month} 月'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('年度页：左上角时间切换弹滚轮选年份', (tester) async {
    setView(tester);

    final now = DateTime.now();
    final dao = await openTempDb(tester);
    await dbCall(
      tester,
      () => dao.insert(
        Txn(
          date: '${isoDate(now.year, now.month, now.day)} 10:00:00',
          direction: 'expense',
          amountCents: 1900,
          category: '餐饮美食',
        ),
      ),
    );

    await tester.pumpWidget(MaterialApp(home: AppShell(dao: dao)));
    await settle(tester);
    await _tapTab(tester, 'tabYear');
    await settle(tester);

    await tester.tap(find.text('${now.year} 年'));
    await settle(tester);
    expect(find.byType(ListWheelScrollView), findsOneWidget, reason: '年度只有一列年');

    await tester.drag(find.byType(ListWheelScrollView), const Offset(0, -50));
    await settle(tester);
    await tester.tap(find.text('确定'));
    await settle(tester);

    expect(find.byType(ListWheelScrollView), findsNothing);
    expect(find.text('${now.year + 1} 年'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
