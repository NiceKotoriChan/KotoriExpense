import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/db.dart';
import 'package:kotori_expense/models.dart';
import 'package:kotori_expense/pages/search_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

const _samples = [
  Txn(
    date: '2026-09-01 10:00:00',
    direction: 'expense',
    amountCents: 100,
    counterparty: '瑞幸咖啡',
    item: '生椰拿铁',
    category: '餐饮美食',
    type: '余额宝',
  ),
  Txn(
    date: '2026-09-02 11:00:00',
    direction: 'expense',
    amountCents: 200,
    counterparty: '京东商城',
    item: '充电器',
    category: '数码电器',
    type: '花呗',
  ),
];

void main() {
  sqfliteFfiInit();

  group('搜索 DAO', () {
    late Database db;
    late TxnDao dao;

    setUp(() async {
      db = await openAppDb(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      dao = TxnDao(db);
      await dao.insertAll(_samples);
    });

    tearDown(() => db.close());

    test('四个字段任意一个命中都算', () async {
      expect(await dao.search('瑞幸'), hasLength(1)); // 交易对象
      expect(await dao.search('充电'), hasLength(1)); // 商品
      expect(await dao.search('数码'), hasLength(1)); // 分类
      expect(await dao.search('花呗'), hasLength(1)); // 类型
      expect(await dao.search('咖啡'), hasLength(1)); // 部分匹配
    });

    test('结果按时间倒序', () async {
      await dao.insertAll(const [
        Txn(
          date: '2026-09-05 09:00:00',
          direction: 'expense',
          amountCents: 100,
          counterparty: 'A咖啡',
        ),
        Txn(
          date: '2026-09-08 09:00:00',
          direction: 'expense',
          amountCents: 100,
          counterparty: 'B咖啡',
        ),
      ]);
      final r = await dao.search('咖啡');
      expect(r.map((t) => t.counterparty).toList(), ['B咖啡', 'A咖啡', '瑞幸咖啡']);
    });

    test('搜不到给空列表', () async {
      expect(await dao.search('不存在的东西'), isEmpty);
    });

    test('空关键词 / 纯空格不当成「搜全部」', () async {
      expect(await dao.search(''), isEmpty);
      expect(await dao.search('   '), isEmpty);
    });

    test('% 和 _ 是字面量，不是通配符', () async {
      await dao.insert(
        const Txn(
          date: '2026-09-03 10:00:00',
          direction: 'expense',
          amountCents: 300,
          counterparty: '100%纯棉',
        ),
      );
      // 不转义的话 % 会匹配所有行
      expect(await dao.search('%'), hasLength(1));
      // 不转义的话 _ 也会匹配所有行
      expect(await dao.search('_'), isEmpty);
    });

    test('limit 生效', () async {
      await dao.insertAll([
        for (var i = 1; i <= 5; i++)
          Txn(
            date: '2026-08-0$i 09:00:00',
            direction: 'expense',
            amountCents: 100,
            counterparty: '批量$i',
          ),
      ]);
      expect(await dao.search('批量'), hasLength(5));
      expect(await dao.search('批量', limit: 2), hasLength(2));
    });
  });

  group('搜索页', () {
    testWidgets('输入关键词出结果并带日期分组', (tester) async {
      setView(tester);
      final dao = await openTempDb(tester);
      await dbCall(tester, () => dao.insertAll(_samples));

      await tester.pumpWidget(MaterialApp(home: SearchPage(dao: dao)));
      await settle(tester);
      expect(find.text('输入关键词开始找'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '瑞幸');
      await settle(tester);
      expect(find.text('找到 1 条'), findsOneWidget);
      expect(find.text('瑞幸咖啡'), findsOneWidget);
      // 日期分组条
      expect(find.textContaining('支出 '), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('搜不到给提示，清空按钮能把结果收回去', (tester) async {
      setView(tester);
      final dao = await openTempDb(tester);
      await dbCall(tester, () => dao.insertAll(_samples));

      await tester.pumpWidget(MaterialApp(home: SearchPage(dao: dao)));
      await settle(tester);

      await tester.enterText(find.byType(TextField), '完全没有的东西');
      await settle(tester);
      expect(find.textContaining('没找到'), findsOneWidget);

      await tester.tap(find.byTooltip('清空'));
      await settle(tester);
      expect(find.text('输入关键词开始找'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
