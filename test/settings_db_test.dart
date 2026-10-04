import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/db.dart';
import 'package:kotori_expense/import/bill_parser.dart';
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

  group('映射规则', () {
    test('没改过就是出厂规则', () async {
      expect((await dao.csvRules()).encode(), kDefaultBillRules.encode());
    });

    test('改名 + 改列名存了能读回来', () async {
      final alipay = kDefaultBillRules.byId('alipay')!;
      await dao.saveCsvRules(
        kDefaultBillRules.upsert(
          alipay.copyWith(
            name: '我的支付宝',
            fields: {...alipay.fields, TxnField.amount: ['交易金额']},
          ),
        ),
      );
      final back = await dao.csvRules();
      expect(back.byId('alipay')!.name, '我的支付宝');
      expect(back.byId('alipay')!.headers(TxnField.amount), ['交易金额']);
      // 其余两条没动
      expect(back.rules, hasLength(3));
    });

    test('新增、删除规则都存得住', () async {
      const custom = BillRule(
        id: 'rule4',
        name: '工行',
        hints: ['摘要'],
        fields: {
          TxnField.date: ['日期'],
          TxnField.direction: ['收支'],
          TxnField.amount: ['金额'],
        },
      );
      await dao.saveCsvRules(kDefaultBillRules.upsert(custom));
      expect((await dao.csvRules()).rules, hasLength(4));

      await dao.saveCsvRules((await dao.csvRules()).remove('rule4'));
      final back = await dao.csvRules();
      expect(back.byId('rule4'), isNull);
      expect(back.rules, hasLength(3));
    });

    test('恢复默认把记录删掉', () async {
      final wechat = kDefaultBillRules.byId('wechat')!;
      await dao.saveCsvRules(
        kDefaultBillRules.upsert(wechat.copyWith(hints: ['X'])),
      );
      expect(await dao.setting(kCsvRulesKey), isNotNull);
      await dao.resetCsvRules();
      expect(await dao.setting(kCsvRulesKey), isNull);
      expect((await dao.csvRules()).encode(), kDefaultBillRules.encode());
    });

    test('库里是坏数据也不炸，落回出厂规则', () async {
      await dao.setSetting(kCsvRulesKey, '{{{ 不是 json');
      expect((await dao.csvRules()).encode(), kDefaultBillRules.encode());
    });
  });

  group('按区间查', () {
    setUp(() async {
      await dao.insertAll(const [
        Txn(
          date: '2026-08-31 23:59:59',
          direction: 'expense',
          amountCents: 100,
        ),
        Txn(
          date: '2026-09-01 00:00:00',
          direction: 'expense',
          amountCents: 200,
        ),
        Txn(date: '2026-09-30 23:59:59', direction: 'income', amountCents: 300),
        Txn(
          date: '2026-10-01 00:00:00',
          direction: 'expense',
          amountCents: 400,
        ),
      ]);
    });

    test('两端都含，边界日不丢', () async {
      final r = await dao.listRange('2026-09-01', '2026-09-30');
      expect(r, hasLength(2));
      expect(r.map((t) => t.amountCents).toList(), [300, 200]); // 时间倒序
    });

    test('跨月的宽区间把边界两头都包进来', () async {
      final r = await dao.listRange('2026-08-31', '2026-10-01');
      expect(r, hasLength(4));
      expect(r.first.amountCents, 400);
      expect(r.last.amountCents, 100);
    });

    test('区间外返回空', () async {
      expect(await dao.listRange('2020-01-01', '2020-12-31'), isEmpty);
    });
  });
}
