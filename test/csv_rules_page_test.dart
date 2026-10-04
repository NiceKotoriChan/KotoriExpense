import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/db.dart';
import 'package:kotori_expense/icons.dart';
import 'package:kotori_expense/import/mapping_rules.dart';
import 'package:kotori_expense/pages/csv_rules_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  sqfliteFfiInit();

  Future<void> open(WidgetTester tester, TxnDao dao) async {
    await tester.pumpWidget(MaterialApp(home: CsvRulesPage(dao: dao)));
    await settle(tester);
  }

  testWidgets('列表页一条条列出规则，加号在最后', (tester) async {
    setView(tester);
    await open(tester, await openTempDb(tester));

    expect(find.text('映射规则'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '支付宝'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '微信'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '招商银行'), findsOneWidget);
    expect(find.text('新增一条规则'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(4));
    // 副标题报字段数和特征列数
    expect(find.textContaining('个字段 · 特征列'), findsNWidgets(3));
  });

  testWidgets('点进规则能改名，返回后列表跟着变', (tester) async {
    setView(tester);
    final dao = await openTempDb(tester);
    await open(tester, dao);

    await tester.tap(find.widgetWithText(ListTile, '招商银行'));
    await settle(tester);

    // 详情页：8 个数据库字段一个不少
    for (final f in TxnField.values) {
      expect(find.text(f.label), findsOneWidget, reason: f.label);
    }
    // 招行的交易类型取自交易摘要
    expect(find.text('交易摘要、交易类型'), findsOneWidget);

    await tester.tap(find.text('规则名称'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '招行储蓄卡');
    await tester.tap(find.text('保存'));
    await settle(tester);

    expect(find.widgetWithText(AppBar, '招行储蓄卡'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settle(tester);

    expect(find.widgetWithText(ListTile, '招行储蓄卡'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '招商银行'), findsNothing);
    expect((await dbCall(tester, dao.csvRules)).byId('cmb')!.name, '招行储蓄卡');
  });

  testWidgets('改字段映射会立刻存库，没配的字段有说明', (tester) async {
    setView(tester);
    final dao = await openTempDb(tester);
    await open(tester, dao);

    await tester.tap(find.widgetWithText(ListTile, '微信'));
    await settle(tester);

    // 微信没有货币列和分类列
    expect(find.text('（留空 → CNY）'), findsOneWidget);
    expect(find.text('（留空）'), findsOneWidget);
    expect(find.text('金额(元)、金额（元）、金额'), findsOneWidget);

    await tester.tap(find.text('交易金额'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '实付金额');
    await tester.tap(find.text('保存'));
    await settle(tester);

    expect(find.text('实付金额'), findsOneWidget);
    final back = await dbCall(tester, dao.csvRules);
    expect(back.byId('wechat')!.headers(TxnField.amount), ['实付金额']);
  });

  testWidgets('新增一条规则后能删掉', (tester) async {
    setView(tester);
    final dao = await openTempDb(tester);
    await open(tester, dao);

    await tester.tap(find.text('新增一条规则'));
    await settle(tester);

    // 新规则还没配关键字段，页面上要说一声
    expect(find.widgetWithText(AppBar, '新规则'), findsOneWidget);
    expect(find.textContaining('三个都得填上列名'), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.resolve('deleteTxn')));
    await settle(tester);
    await tester.tap(find.text('删除'));
    await settle(tester);

    expect(find.widgetWithText(ListTile, '新规则'), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(4)); // 回到 3 条 + 新增
    expect((await dbCall(tester, dao.csvRules)).rules, hasLength(3));
  });
}
