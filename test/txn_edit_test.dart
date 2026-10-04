import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/db.dart';
import 'package:kotori_expense/models.dart';
import 'package:kotori_expense/pages/txn_edit_page.dart' as edit;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 走一遍真实路径：从上一个页面 push 进去，这样 pop 才有得弹。
Future<void> _pushEditor(WidgetTester tester, TxnDao dao, [Txn? txn]) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).push(
              MaterialPageRoute(
                builder: (_) => edit.TxnEditPage(dao: dao, txn: txn),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await settle(tester);
}

void main() {
  sqfliteFfiInit();

  group('DAO 层', () {
    late Database db;
    late TxnDao dao;

    setUp(() async {
      db = await openAppDb(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      dao = TxnDao(db);
    });

    tearDown(() => db.close());

    const base = Txn(
      date: '2026-09-01 10:00:00',
      direction: 'expense',
      amountCents: 1234,
      counterparty: 'A',
    );

    test('改一条：字段覆盖，行数不变', () async {
      final id = await dao.insert(base);
      await dao.update(
        Txn(
          id: id,
          date: '2026-09-02 11:00:00',
          direction: 'income',
          amountCents: 200,
          counterparty: 'B',
          category: '餐饮美食',
        ),
      );

      final t = await dao.findById(id);
      expect(t!.amountCents, 200);
      expect(t.direction, 'income');
      expect(t.counterparty, 'B');
      expect(t.category, '餐饮美食');
      expect(await dao.count(), 1);
    });

    test('改的时候不会把 id 一起写进去（toMap 里带着 id）', () async {
      final id = await dao.insert(base);
      await dao.update(
        Txn(
          id: id,
          date: '2026-09-03 10:00:00',
          direction: 'expense',
          amountCents: 500,
        ),
      );
      expect(await dao.findById(id), isNotNull);
      expect(await dao.count(), 1);
    });

    test('清空可选字段能落库成 NULL', () async {
      final id = await dao.insert(base);
      await dao.update(
        Txn(id: id, date: base.date, direction: 'expense', amountCents: 1234),
      );
      final t = await dao.findById(id);
      expect(t!.counterparty, isNull);
      expect(t.category, isNull);
    });

    test('没有 id 的 Txn 不能拿去改', () async {
      expect(() => dao.update(base), throwsArgumentError);
    });

    test('删一条', () async {
      final id = await dao.insert(base);
      expect(await dao.deleteTxn(id), 1);
      expect(await dao.count(), 0);
      expect(await dao.findById(id), isNull);
    });

    test('findById 查不到给 null', () async {
      expect(
        await dao.findById('0192f0a0-0000-7000-8000-0000000000ff'),
        isNull,
      );
    });

    test('knownCategories 是流水分类和配置分类的并集，去重且排序', () async {
      await dao.insert(
        const Txn(
          date: '2026-09-01 10:00:00',
          direction: 'expense',
          amountCents: 100,
          category: '自己瞎写的',
        ),
      );
      // 再加一条重复分类，不该出现两次
      await dao.insert(
        const Txn(
          date: '2026-09-02 10:00:00',
          direction: 'expense',
          amountCents: 100,
          category: '自己瞎写的',
        ),
      );

      final list = await dao.knownCategories();
      expect(list.toSet().length, list.length, reason: '有重复');
      expect(list, contains('自己瞎写的'));
      expect(list, contains('餐饮美食')); // 来自 category_icon 播种
      expect(list, orderedEquals(List.of(list)..sort()));
    });
  });

  group('记账页', () {
    testWidgets('填个金额就能记下', (tester) async {
      setView(tester, height: 1000);
      final dao = await openTempDb(tester);

      await _pushEditor(tester, dao);
      expect(find.text('记一笔'), findsOneWidget);
      expect(find.byTooltip('删除'), findsNothing, reason: '新增时不该有删除');

      await tester.enterText(find.byType(TextField).first, '12.34');
      await tester.tap(find.text('记下'));
      await settle(tester);

      expect(find.text('记一笔'), findsNothing, reason: '存完应该退回上一页');

      final rows = await dbCall(tester, dao.listAll);
      expect(rows, hasLength(1));
      expect(rows.single.amountCents, 1234); // 12.34 元 = 1234 分
      expect(rows.single.direction, 'expense');
      expect(rows.single.currency, 'CNY');
      expect(tester.takeException(), isNull);
    });

    testWidgets('金额空着或为 0 时不让存，给出提示', (tester) async {
      setView(tester, height: 1000);
      final dao = await openTempDb(tester);

      await _pushEditor(tester, dao);
      await tester.tap(find.text('记下'));
      await settle(tester);
      expect(find.text('金额要填一个大于 0 的数'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '0');
      await tester.tap(find.text('记下'));
      await settle(tester);
      expect(find.text('金额要填一个大于 0 的数'), findsOneWidget);

      expect(await dbCall(tester, dao.count), 0);
      expect(find.text('记一笔'), findsOneWidget, reason: '不该退页');
    });

    testWidgets('切成收入再记，方向要跟着变', (tester) async {
      setView(tester, height: 1000);
      final dao = await openTempDb(tester);

      await _pushEditor(tester, dao);
      await tester.tap(find.text('收入').last);
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '88');
      await tester.tap(find.text('记下'));
      await settle(tester);

      final rows = await dbCall(tester, dao.listAll);
      expect(rows.single.direction, 'income');
      expect(rows.single.amountCents, 8800);
    });
  });

  group('详情页', () {
    const draft = Txn(
      date: '2026-09-01 10:00:00',
      direction: 'expense',
      amountCents: 1234,
      counterparty: 'A',
    );

    /// 详情页得拿一个库里真有的 id，才改得到那一行
    Txn stored(String id) => Txn(
      id: id,
      date: draft.date,
      direction: draft.direction,
      amountCents: draft.amountCents,
      counterparty: draft.counterparty,
    );

    testWidgets('改金额是覆盖，不是新增', (tester) async {
      setView(tester, height: 1000);
      final dao = await openTempDb(tester);
      final id = await dbCall(tester, () => dao.insert(draft));

      await _pushEditor(tester, dao, stored(id));
      expect(find.text('账单详情'), findsOneWidget);
      expect(find.text('保存修改'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '99.00');
      await tester.tap(find.text('保存修改'));
      await settle(tester);

      final after = await dbCall(tester, () => dao.findById(id));
      expect(after!.amountCents, 9900);
      expect(after.counterparty, 'A', reason: '没碰的字段不该被清掉');
      expect(after.date, '2026-09-01 10:00:00', reason: '日期没动过');
      expect(await dbCall(tester, dao.count), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('删除要确认，确认后这条就没了', (tester) async {
      setView(tester, height: 1000);
      final dao = await openTempDb(tester);
      final id = await dbCall(tester, () => dao.insert(draft));

      await _pushEditor(tester, dao, stored(id));
      await tester.tap(find.byTooltip('删除'));
      await settle(tester);
      expect(find.text('删除这条流水？'), findsOneWidget);

      // 先点取消，数据不该动
      await tester.tap(find.text('取消'));
      await settle(tester);
      expect(await dbCall(tester, dao.count), 1);

      await tester.tap(find.byTooltip('删除'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await settle(tester);

      expect(await dbCall(tester, dao.count), 0);
      expect(find.text('账单详情'), findsNothing, reason: '删完应该退回上一页');
      expect(tester.takeException(), isNull);
    });
  });
}
