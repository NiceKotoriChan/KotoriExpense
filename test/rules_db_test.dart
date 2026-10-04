import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/db.dart';
import 'package:kotori_expense/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  BillRule rule(String name) => BillRule(
    name: name,
    headers: const {
      'date': '日期',
      'direction': '收支',
      'amount': '金额',
      'item': '备注',
    },
  );

  test('建库不带任何出厂规则', () async {
    expect(await dao.rules(), isEmpty);
  });

  test('存进去能原样读回来，没配的列是 null', () async {
    await dao.saveRule(rule('工行'));
    final r = (await dao.rules()).single;
    expect(r.name, '工行');
    expect(r.header('item'), '备注');
    expect(r.header('category'), isNull);
    expect(r.header('currency'), isNull);
    expect(r.isUsable, isTrue);
  });

  test('同样的名字再存就是改，不会多一行', () async {
    await dao.saveRule(rule('工行'));
    final headers = {...rule('工行').headers, 'amount': '交易金额'};
    await dao.saveRule(rule('工行').copyWith(headers: headers));

    final all = await dao.rules();
    expect(all, hasLength(1));
    expect(all.single.header('amount'), '交易金额');
  });

  test('改名是改主键，行还是那一行、顺序也不动', () async {
    await dao.saveRule(rule('工行'));
    await dao.saveRule(rule('建行'));
    await dao.renameRule('工行', '工行储蓄卡');

    final all = await dao.rules();
    expect(all.map((r) => r.name).toList(), ['工行储蓄卡', '建行']);
    expect(all.first.header('amount'), '金额');
  });

  test('改成已有的名字会被主键挡住', () async {
    await dao.saveRule(rule('工行'));
    await dao.saveRule(rule('建行'));
    await expectLater(
      dao.renameRule('建行', '工行'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('删掉就没了', () async {
    await dao.saveRule(rule('工行'));
    await dao.saveRule(rule('建行'));
    await dao.deleteRule('工行');
    expect((await dao.rules()).map((r) => r.name).toList(), ['建行']);
  });

  test('rules 表 NOT NULL 的列挡住半条规则', () async {
    await expectLater(
      db.insert('rules', {'name': '半条'}),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('重开数据库不会覆盖用户改过的列名', () async {
    final dir = Directory.systemTemp.createTempSync('kotori_rules');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/t.db';

    final first = await openAppDb(path: path, factory: databaseFactoryFfi);
    await TxnDao(first).saveRule(rule('工行'));
    final icbc = (await TxnDao(first).rules()).single;
    await TxnDao(first)
        .saveRule(icbc.copyWith(headers: {...icbc.headers, 'amount': '交易金额'}));
    await first.close();

    final second = await openAppDb(path: path, factory: databaseFactoryFfi);
    expect((await TxnDao(second).rules()).single.header('amount'), '交易金额');
    await second.close();
  });
}
