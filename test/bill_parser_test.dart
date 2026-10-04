import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/import/bill_parser.dart';

List<int> _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  group('支付宝账单', () {
    late ParseResult r;
    setUpAll(() => r = parseBillBytes(_fixture('alipay_sample.csv')));

    test('认出是支付宝', () {
      expect(r.sourceName, '支付宝');
    });

    test('6 行数据全部解析成功', () {
      expect(r.dataRowCount, 6);
      expect(r.txns, hasLength(6));
      expect(r.issues, isEmpty);
    });

    test('字段映射正确', () {
      final t = r.txns.first;
      expect(t.date, '2026-09-03 08:30:12');
      expect(t.direction, 'expense');
      expect(t.amountCents, 1900);
      expect(t.type, '余额宝'); // 收/付款方式
      expect(t.counterparty, '瑞幸咖啡(北京朝阳门店)');
      expect(t.item, '生椰拿铁');
      expect(t.category, '餐饮美食'); // 支付宝自带的分类
    });

    test('账单里没有货币列，补 CNY', () {
      expect(r.txns.every((t) => t.currency == 'CNY'), isTrue);
    });

    test('带千分位的金额也认得', () {
      final t = r.txns.firstWhere((e) => e.counterparty == '京东商城');
      expect(t.amountCents, 129900);
    });

    test('收入行方向正确', () {
      final t = r.txns.firstWhere((e) => e.counterparty == '张三');
      expect(t.direction, 'income');
      expect(t.amountCents, 20000);
    });
  });

  group('微信账单', () {
    late ParseResult r;
    setUpAll(() => r = parseBillBytes(_fixture('wechat_sample.csv')));

    test('认出是微信', () {
      expect(r.sourceName, '微信');
    });

    test('6 行数据，跳过 1 条不计收支', () {
      expect(r.dataRowCount, 6);
      expect(r.txns, hasLength(5));
      expect(r.issues, hasLength(1));
      expect(r.issues.first.reason, contains('不计入收支'));
    });

    test('字段映射正确（微信没有分类列）', () {
      final t = r.txns.first;
      expect(t.date, '2026-09-02 08:15:33');
      expect(t.amountCents, 2200); // '¥22.00'
      expect(t.type, '零钱'); // 支付方式
      expect(t.counterparty, '肯德基');
      expect(t.item, '早餐套餐');
      expect(t.category, isNull);
    });

    test('红包收入也能识别', () {
      final t = r.txns.firstWhere((e) => e.counterparty == '王五');
      expect(t.direction, 'income');
      expect(t.amountCents, 6600);
    });
  });

  group('招行账单', () {
    late ParseResult r;
    setUpAll(() => r = parseBillBytes(_fixture('cmb_sample.csv')));

    test('认出是招商银行', () {
      expect(r.sourceName, '招商银行');
    });

    test('4 行数据，跳过 1 条不计收支', () {
      expect(r.dataRowCount, 4);
      expect(r.txns, hasLength(3));
      expect(r.issues, hasLength(1));
      expect(r.issues.first.reason, contains('不计入收支'));
    });

    test('交易摘要当交易类型，交易备注当交易商品', () {
      final t = r.txns.first;
      expect(t.date, '2026-09-05 12:30:00');
      expect(t.direction, 'expense');
      expect(t.amountCents, 3500);
      expect(t.type, '星巴克咖啡'); // 交易摘要
      expect(t.counterparty, '星巴克(国贸店)');
      expect(t.item, '拿铁大杯'); // 交易备注
      expect(t.category, isNull); // 招行没有分类列
      expect(t.currency, 'CNY'); // 货币列的「人民币」
    });

    test('货币列写美元就存 USD', () {
      final t = r.txns.firstWhere((e) => e.counterparty == '京东商城');
      expect(t.currency, 'USD');
    });

    test('收入行方向正确', () {
      final t = r.txns.firstWhere((e) => e.type == '工资代发');
      expect(t.direction, 'income');
      expect(t.amountCents, 1800000);
    });
  });

  group('通用工具', () {
    test('金额 -> 分', () {
      expect(parseAmountCents('19.00'), 1900);
      expect(parseAmountCents('¥1,299.00'), 129900);
      expect(parseAmountCents('3.5'), 350);
      expect(parseAmountCents('0.01'), 1);
      expect(parseAmountCents('1299'), 129900);
      expect(parseAmountCents('-19.00'), -1900);
      expect(parseAmountCents('/'), isNull);
      expect(parseAmountCents(''), isNull);
      expect(parseAmountCents('abc'), isNull);
    });

    test('日期归一化', () {
      expect(normalizeDateTime('2026-09-03 08:30:12'), '2026-09-03 08:30:12');
      expect(normalizeDateTime('2026/9/3 8:30'), '2026-09-03 08:30:00');
      expect(normalizeDateTime('2026-09-03'), '2026-09-03 00:00:00');
      expect(normalizeDateTime('乱码'), isNull);
    });

    test('收支归一化', () {
      expect(parseDirection('支出'), 'expense');
      expect(parseDirection('收入'), 'income');
      expect(parseDirection('/'), isNull);
      expect(parseDirection('不计收支'), isNull);
    });

    test('货币归一化', () {
      expect(normalizeCurrency(null), 'CNY');
      expect(normalizeCurrency(''), 'CNY');
      expect(normalizeCurrency('人民币'), 'CNY');
      expect(normalizeCurrency('cny'), 'CNY');
      expect(normalizeCurrency('美元'), 'USD');
      expect(normalizeCurrency('港币'), 'HKD');
      expect(normalizeCurrency('日元'), 'JPY');
      expect(normalizeCurrency('EUR'), 'EUR');
      expect(normalizeCurrency('什么鬼'), 'CNY');
    });

    test('认不出的文本不炸，给出说明', () {
      final r = parseBillText('随便什么内容\n第二行');
      expect(r.sourceName, isEmpty);
      expect(r.txns, isEmpty);
      expect(r.issues, isNotEmpty);
    });

    test('GBK 与 UTF-8 都能解', () {
      expect(decodeBillBytes([0xE4, 0xB8, 0xAD]), '中'); // UTF-8 的「中」
      expect(decodeBillBytes([0xD6, 0xD0]), '中'); // GBK 的「中」
    });
  });
}
