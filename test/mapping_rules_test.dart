import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/import/bill_parser.dart';

void main() {
  final alipay = kDefaultBillRules.byId('alipay')!;
  final wechat = kDefaultBillRules.byId('wechat')!;
  final cmb = kDefaultBillRules.byId('cmb')!;

  test('出厂三家规则都能用', () {
    expect(kDefaultBillRules.rules, hasLength(3));
    for (final r in kDefaultBillRules.rules) {
      expect(r.isUsable, isTrue, reason: '${r.name} 少了时间 / 收支 / 金额');
      expect(r.hints, isNotEmpty, reason: '${r.name} 没配特征列');
    }
    // 微信和招行本来就没有分类列
    expect(wechat.headers(TxnField.category), isEmpty);
    expect(cmb.headers(TxnField.category), isEmpty);
    // 招行的「交易类型」取自交易摘要
    expect(cmb.headers(TxnField.type), contains('交易摘要'));
    // 支付宝有分类列
    expect(alipay.headers(TxnField.category), ['交易分类']);
  });

  test('字段表就是 transactions 的列，顺序照 docs/sql.md', () {
    expect(TxnField.values.map((f) => f.label).toList(), [
      '交易时间',
      '交易类型',
      '交易对象',
      '交易商品',
      '交易货币',
      '交易收支',
      '交易金额',
      '交易分类',
    ]);
  });

  test('关键字段只有时间 / 收支 / 金额，货币和分类不算', () {
    expect(kKeyFields, [TxnField.date, TxnField.direction, TxnField.amount]);
  });

  group('存取', () {
    test('改名 + 改列名，来回一趟不变', () {
      final modified = kDefaultBillRules.upsert(
        alipay.copyWith(
          name: '我的支付宝',
          hints: ['自定义特征'],
          fields: {...alipay.fields, TxnField.amount: ['交易金额']},
        ),
      );
      final back = BillRules.decode(modified.encode());
      final r = back.byId('alipay')!;
      expect(r.name, '我的支付宝');
      expect(r.hints, ['自定义特征']);
      expect(r.headers(TxnField.amount), ['交易金额']);
      expect(back.rules, hasLength(3));
      // 没动过的来源还是出厂值
      expect(
        back.byId('wechat')!.headers(TxnField.amount),
        wechat.headers(TxnField.amount),
      );
    });

    test('空值 / 坏 JSON / 非对象都落回出厂规则，不抛异常', () {
      expect(BillRules.decode(null).encode(), kDefaultBillRules.encode());
      expect(BillRules.decode('').encode(), kDefaultBillRules.encode());
      expect(BillRules.decode('这不是 json').encode(), kDefaultBillRules.encode());
      expect(BillRules.decode('[1,2,3]').encode(), kDefaultBillRules.encode());
    });

    test('旧格式（平铺对象）也能读进来，不用重配', () {
      final back = BillRules.decode(
        '{"alipay":{"fields":{"amount":["交易金额"]}},"wechat":{"hints":["X"]}}',
      );
      final a = back.byId('alipay')!;
      expect(a.name, '支付宝'); // 名字还是出厂的
      expect(a.headers(TxnField.amount), ['交易金额']);
      expect(a.headers(TxnField.date), alipay.headers(TxnField.date)); // 缺的用出厂值补
      expect(a.hints, alipay.hints);
      expect(back.byId('wechat')!.hints, ['X']);
      expect(back.byId('cmb'), isNotNull);
    });

    test('旧数据缺字段时用出厂值补上', () {
      final back = BillRules.decode('{"rules":[{"id":"alipay","fields":{}}]}');
      final r = back.byId('alipay')!;
      expect(r.name, '支付宝');
      expect(r.headers(TxnField.amount), alipay.headers(TxnField.amount));
      expect(r.hints, alipay.hints);
    });

    test('新增的规则能存能读，删掉就不会再回来', () {
      const custom = BillRule(
        id: 'rule4',
        name: '工行储蓄卡',
        hints: ['摘要'],
        fields: {
          TxnField.date: ['交易日期'],
          TxnField.direction: ['收支'],
          TxnField.amount: ['金额'],
        },
      );
      final added = BillRules.decode(kDefaultBillRules.upsert(custom).encode());
      expect(added.rules, hasLength(4));
      expect(added.byId('rule4')!.name, '工行储蓄卡');

      final cut = BillRules.decode(added.remove('rule4').encode());
      expect(cut.byId('rule4'), isNull);
      expect(cut.rules, hasLength(3));

      // 全删光就是空的，不硬塞回出厂规则
      expect(BillRules.decode(const BillRules([]).encode()).rules, isEmpty);
    });

    test('重复 / 缺 id / 不是对象的条目会被跳过', () {
      final back = BillRules.decode(
        '{"rules":[{"id":"","name":"没 id"},'
        '{"id":"a","name":"A","hints":[],"fields":{}},'
        '{"id":"a","name":"重复"}, "不是对象", 42]}',
      );
      expect(back.rules, hasLength(1));
      expect(back.byId('a')!.name, 'A');
    });

    test('nextId 跳过已占用的 id', () {
      const custom = BillRule(id: 'rule4', name: 'X', hints: [], fields: {});
      final rules = kDefaultBillRules.upsert(custom);
      expect(rules.nextId(), 'rule5');
      expect(rules.byId(rules.nextId()), isNull);
    });

    test('restoreDefault 只对出厂规则有效', () {
      final changed = kDefaultBillRules.upsert(
        alipay.copyWith(name: '改过的', hints: []),
      );
      expect(changed.byId('alipay')!.name, '改过的');
      final back = changed.restoreDefault('alipay');
      expect(back.byId('alipay')!.name, '支付宝');
      expect(back.byId('alipay')!.hints, alipay.hints);

      const mine = BillRule(id: 'rule9', name: '我的', hints: [], fields: {});
      expect(
        back.upsert(mine).restoreDefault('rule9').byId('rule9')!.name,
        '我的',
      );
    });
  });

  group('按规则解析', () {
    test('改了候选列名之后，新列名能认出来', () {
      final rules = kDefaultBillRules.upsert(
        alipay.copyWith(
          fields: {...alipay.fields, TxnField.amount: ['交易金额']},
        ),
      );
      final rows = [
        ['交易时间', '收/支', '交易金额', '交易对方'],
        ['2026-09-01 10:00:00', '支出', '12.34', '测试商家'],
      ];
      final r = parseRowsAs(rows, 'alipay', rules);
      expect(r.txns, hasLength(1));
      expect(r.txns.first.amountCents, 1234);
      expect(r.txns.first.counterparty, '测试商家');
      expect(r.sourceName, '支付宝');
    });

    test('同一张表用出厂规则就认不出表头', () {
      final rows = [
        ['交易时间', '收/支', '交易金额', '交易对方'],
        ['2026-09-01 10:00:00', '支出', '12.34', '测试商家'],
      ];
      final r = parseRowsAs(rows, 'alipay');
      expect(r.txns, isEmpty);
      expect(r.issues.first.reason, contains('找不到表头行'));
    });

    test('id 不存在时给出说明，不炸', () {
      final r = parseRowsAs(const [], '不存在的规则');
      expect(r.txns, isEmpty);
      expect(r.issues.first.reason, contains('不存在的规则'));
    });

    test('特征列被清空后认不出来源', () {
      final rules = kDefaultBillRules.upsert(alipay.copyWith(hints: []));
      final rows = [
        ['交易时间', '收/支', '金额'],
        ['2026-09-01 10:00:00', '支出', '1.00'],
      ];
      expect(sniffRule(rows, rules), isNull);
    });

    test('候选列名可以多个，按顺序取第一个命中的', () {
      final rules = kDefaultBillRules.upsert(
        wechat.copyWith(
          fields: {...wechat.fields, TxnField.amount: ['应退金额', '金额']},
        ),
      );
      final rows = [
        ['交易时间', '收/支', '应退金额', '金额', '交易单号'],
        ['2026-09-01 10:00:00', '支出', '1.00', '9.90', 'X1'],
      ];
      final r = parseRowsAs(rows, 'wechat', rules);
      expect(r.txns.first.amountCents, 100);
    });

    test('规则改了名，正文里的新名字也能兜住来源', () {
      final rules = kDefaultBillRules.upsert(
        alipay.copyWith(name: '我的支付宝', hints: []),
      );
      final rows = [
        ['日期', '收/支', '金额', '备注'],
        ['2026-09-01', '支出', '1.00', '支付宝'],
        ['这是我的支付宝账单'],
      ];
      expect(sniffRule(rows, rules)?.id, 'alipay');
    });

    test('认不出来源时提示里列出现有规则名', () {
      final r = parseBillText('随便什么内容\n第二行');
      expect(r.sourceName, isEmpty);
      expect(r.txns, isEmpty);
      expect(r.issues.first.reason, contains('支付宝'));
      expect(r.issues.first.reason, contains('招商银行'));
    });

    test('一条规则都没有时，提示先去加规则', () {
      final r = parseBillText('日期,金额\n2026-09-01,1.00', const BillRules([]));
      expect(r.txns, isEmpty);
      expect(r.issues.first.reason, contains('一条映射规则都没有'));
    });
  });
}
