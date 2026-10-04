import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/db.dart';
import 'package:kotori_expense/import/bill_parser.dart';
import 'package:kotori_expense/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// uuidv7 的形状：36 位，版本位是 7，变体位是 8/9/a/b
final _uuidV7 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  sqfliteFfiInit();

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

  test('表结构与 docs/sql.md 对齐', () async {
    final cols = await db.rawQuery('PRAGMA table_info(transactions)');
    expect(cols.map((c) => c['name']).toList(), [
      'id',
      'date',
      'currency',
      'type',
      'counterparty',
      'item',
      'direction',
      'cents',
      'category',
    ]);
  });

  test('id 是 DAO 生成的 uuidv7', () async {
    final id = await dao.insert(
      const Txn(
        date: '2026-01-01 00:00:00',
        direction: 'expense',
        amountCents: 1,
      ),
    );
    expect(id, matches(_uuidV7));

    final back = await dao.findById(id);
    expect(back!.id, id);
    expect(back.amountCents, 1);
  });

  test('Txn 自带 id 时就用它，不另外生成', () async {
    final id = await dao.insert(
      const Txn(
        id: '0192f0a0-0000-7000-8000-000000000001',
        date: '2026-01-01 00:00:00',
        direction: 'expense',
        amountCents: 2,
      ),
    );
    expect(id, '0192f0a0-0000-7000-8000-000000000001');
    expect(await dao.count(), 1);
  });

  test('支付宝样例导入后能查回来，金额单位是分', () async {
    final r = parseBillBytes(
      File('test/fixtures/alipay_sample.csv').readAsBytesSync(),
    );
    final n = await dao.insertAll(r.txns);
    expect(n, 6);
    expect(await dao.count(), 6);

    final list = await dao.listAll();
    expect(list, hasLength(6));
    // 批量导入也逐行给 id，且互不相同
    final ids = list.map((t) => t.id).toList();
    expect(ids, everyElement(matches(_uuidV7)));
    expect(ids.toSet(), hasLength(6));

    // 按时间倒序
    expect(list.first.date.compareTo(list.last.date) > 0, isTrue);
    expect(list.first.date, '2026-09-20 14:22:18');
    expect(list.last.date, '2026-09-03 08:30:12');

    final sum = await dao.summary();
    expect(sum.count, 6);
    expect(sum.incomeCents, 20000);
    expect(sum.expenseCents, 1900 + 3250 + 15800 + 4560 + 129900);
  });

  test('CHECK 约束拦住非法数据', () async {
    await expectLater(
      dao.insert(
        const Txn(
          date: '2026-01-01 00:00:00',
          direction: 'out',
          amountCents: 100,
        ),
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      dao.insert(
        const Txn(
          date: '2026-01-01 00:00:00',
          direction: 'expense',
          amountCents: -1,
        ),
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('微信样例：5 条入库，1 条不计收支被跳过', () async {
    final r = parseBillBytes(
      File('test/fixtures/wechat_sample.csv').readAsBytesSync(),
    );
    expect(r.txns, hasLength(5));
    expect(r.skipped, 1);

    await dao.insertAll(r.txns);
    expect(await dao.count(), 5);

    // 微信那份没有分类列，全部应为 NULL，留给规则匹配
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM transactions WHERE category IS NULL',
    );
    expect(rows.first['c'], 5);
  });

  test('两份账单一起导入互不干扰', () async {
    final a = parseBillBytes(
      File('test/fixtures/alipay_sample.csv').readAsBytesSync(),
    );
    final w = parseBillBytes(
      File('test/fixtures/wechat_sample.csv').readAsBytesSync(),
    );
    await dao.insertAll(a.txns);
    await dao.insertAll(w.txns);
    expect(await dao.count(), 11);
  });
}
