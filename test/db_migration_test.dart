import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// uuidv7 的形状
final _uuidV7 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// v4 的老表结构。冻结在这里，用来造一个「升级前」的库 ——
/// 改了它这个测试就没意义了。
const _v4Transactions = '''
CREATE TABLE transactions (
    id              INTEGER PRIMARY KEY,
    date            TEXT    NOT NULL,
    currency        TEXT    NOT NULL DEFAULT 'CNY',
    type            TEXT,
    counterparty    TEXT,
    item            TEXT,
    direction       TEXT    NOT NULL CHECK (direction IN ('income', 'expense')),
    amount_cents    INTEGER NOT NULL CHECK (amount_cents > 0),
    category        TEXT
)
''';

const _v4CategoryIcon = '''
CREATE TABLE category_icon (
    category  TEXT PRIMARY KEY,
    icon_name TEXT NOT NULL
)
''';

const _v4Settings = '''
CREATE TABLE settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
)
''';

void main() {
  sqfliteFfiInit();

  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('kotori_migrate'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // 库还开着时删不掉也无所谓
    }
  });

  /// 造一个 v4 的库：老表结构 + 两条流水 + 分类图标 + 一条设置
  Future<String> seedV4() async {
    final path = '${dir.path}/app.db';
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await db.execute(_v4Transactions);
          await db.execute(_v4CategoryIcon);
          await db.execute(_v4Settings);
        },
      ),
    );
    await db.insert('transactions', {
      'date': '2026-09-01 10:00:00',
      'currency': 'CNY',
      'direction': 'expense',
      'amount_cents': 1234,
      'counterparty': 'A',
      'category': '餐饮美食',
    });
    // 和上一条同一秒：升级后这两行会拿到同一个毫秒时间戳，
    // v7 的随机区没有顺序含义，只能保证 id 不同、数据不串
    await db.insert('transactions', {
      'date': '2026-09-01 10:00:00',
      'currency': 'CNY',
      'direction': 'expense',
      'amount_cents': 500,
      'counterparty': 'B',
    });
    await db.insert('transactions', {
      'date': '2026-09-02 11:00:00',
      'currency': 'CNY',
      'direction': 'income',
      'amount_cents': 20000,
    });
    await db.insert('category_icon', {
      'category': '餐饮美食',
      'icon_name': 'restaurant',
    });
    await db.insert('settings', {'key': kCsvRulesKey, 'value': '{"rules":[]}'});
    await db.close();
    return path;
  }

  test('v4 -> v5：列名换新，数据一条不丢，金额还是分', () async {
    final db = await openAppDb(
      path: await seedV4(),
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);
    final dao = TxnDao(db);

    final cols = (await db.rawQuery(
      'PRAGMA table_info(transactions)',
    )).map((c) => c['name']).toList();
    expect(cols, contains('cents'));
    expect(cols, isNot(contains('amount_cents')));

    expect(await dao.count(), 3);
    final list = await dao.listAll();
    // 09-02 那行时间最晚，稳定排第一
    expect(list.first.date, '2026-09-02 11:00:00');
    expect(list.first.amountCents, 20000);
    expect(list.first.counterparty, isNull);

    // 同一秒的两行谁在前是随机的，按内容认，不按位置认
    final byParty = {for (final t in list) t.counterparty: t};
    expect(byParty['A']!.amountCents, 1234);
    expect(byParty['A']!.category, '餐饮美食');
    expect(byParty['B']!.amountCents, 500);
  });

  test('v4 -> v5：老行换到 uuidv7，且 id 的顺序跟着 date', () async {
    final db = await openAppDb(
      path: await seedV4(),
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);
    final dao = TxnDao(db);

    final list = await dao.listAll();
    for (final t in list) {
      expect(t.id, matches(_uuidV7));
    }
    // listAll 按 date 倒序，id 是照着 date 生成的，所以也该是倒序
    expect(list.first.id!.compareTo(list.last.id!) > 0, isTrue);

    // 同一秒的两行拿到同一个毫秒（id 前 48 位＝前 12 个十六进制字符），
    // 但 id 必须仍然互不相同
    final byParty = {for (final t in list) t.counterparty: t};
    final a = byParty['A']!.id!;
    final b = byParty['B']!.id!;
    expect(a, isNot(b));
    expect(a.substring(0, 12), b.substring(0, 12));

    // 老 id 是整数，升级后仍能按新 id 查到
    expect(await dao.findById(list.last.id!), isNotNull);
  });

  test('v4 -> v5：分类图标表改名，设置原文不动', () async {
    final db = await openAppDb(
      path: await seedV4(),
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);
    final dao = TxnDao(db);

    final iconCols = (await db.rawQuery(
      'PRAGMA table_info(category_icon)',
    )).map((c) => c['name']).toList();
    expect(iconCols, contains('icon'));
    expect(iconCols, isNot(contains('icon_name')));

    expect((await dao.categoryIcons())['餐饮美食'], 'restaurant');
    // 设置那条 JSON 原样搬过来，没被升级逻辑覆盖
    expect(await dao.setting(kCsvRulesKey), '{"rules":[]}');
    expect((await dao.csvRules()).rules, isEmpty);
  });
}
