import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/db.dart';
import 'package:kotori_expense/models.dart';
import 'package:kotori_expense/pages/bill_rules_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late TxnDao dao;

  setUp(() async {
    // 必须用 NoIsolate 版：默认的 databaseFactoryFfi 把 SQLite 放在后台 isolate 里，
    // 回复走真实事件循环，而 testWidgets 的 body 跑在假时钟里 —— 回复永远送不到，
    // await 就死等、页面停在转圈上，pumpAndSettle 超时。
    db = await openAppDb(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    dao = TxnDao(db);
  });

  tearDown(() => db.close());

  /// 表单有 9 个输入框，小窗口装不下后面几个，给个高一点的画布
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: BillRulesPage(dao: dao)));
    await tester.pumpAndSettle();
  }

  /// 名字 + 三列必需列（index 0 是名字，接着按 BillRule.columns 的顺序）
  Future<void> fillRequired(WidgetTester tester, String name) async {
    final f = find.byType(TextField);
    await tester.enterText(f.at(0), name);
    await tester.enterText(f.at(1), '日期');
    await tester.enterText(f.at(2), '收支');
    await tester.enterText(f.at(3), '金额');
  }

  testWidgets('微信和支付宝置顶而且改不了', (tester) async {
    await pumpPage(tester);

    expect(find.text('微信'), findsOneWidget);
    expect(find.text('支付宝'), findsOneWidget);
    expect(find.text('内置，列名写死在代码里，改不了'), findsNWidgets(2));

    // 只有这两条是 disabled 的，也就是「无法修改」
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
    expect(tiles.where((t) => t.enabled == false), hasLength(2));

    expect(find.textContaining('还没有自定义解析方式'), findsOneWidget);
    expect(find.byTooltip('删除'), findsNothing);
  });

  testWidgets('新建一条：默认名字不撞，存住后出现在列表里', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('新建解析方式'), findsOneWidget);
    final first = tester.widget<TextField>(find.byType(TextField).first);
    expect(first.controller!.text, '新规则');

    await fillRequired(tester, '工行');
    await tester.tap(find.text('建好'));
    await tester.pumpAndSettle();

    expect(find.text('工行'), findsOneWidget);
    expect(find.textContaining('交易时间＝日期'), findsOneWidget);
    expect((await dao.rules()).single.name, '工行');
  });

  testWidgets('必需列没配齐不让存', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '工行');
    await tester.enterText(find.byType(TextField).at(1), '日期');
    await tester.tap(find.text('建好'));
    await tester.pumpAndSettle();

    expect(find.textContaining('必须配'), findsOneWidget);
    expect(await dao.rules(), isEmpty);
  });

  testWidgets('改名存得住，行没有变多', (tester) async {
    const icbc = BillRule(
      name: '工行',
      headers: {'date': '日期', 'direction': '收支', 'amount': '金额'},
    );
    await dao.saveRule(icbc);
    await pumpPage(tester);

    await tester.tap(find.text('工行'));
    await tester.pumpAndSettle();
    expect(find.text('编辑解析方式'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '工行储蓄卡');
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(find.text('工行储蓄卡'), findsOneWidget);
    expect(find.text('工行'), findsNothing);
    final all = await dao.rules();
    expect(all, hasLength(1));
    expect(all.single.name, '工行储蓄卡');
    expect(all.single.header('amount'), '金额');
  });

  testWidgets('删掉要确认，确认后就没了', (tester) async {
    const icbc = BillRule(
      name: '工行',
      headers: {'date': '日期', 'direction': '收支', 'amount': '金额'},
    );
    await dao.saveRule(icbc);
    await pumpPage(tester);

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删掉这个解析方式？'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('工行'), findsNothing);
    expect(await dao.rules(), isEmpty);
    expect(find.textContaining('还没有自定义解析方式'), findsOneWidget);
  });
}
