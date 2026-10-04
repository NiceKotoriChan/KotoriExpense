import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/import/alipay_parser.dart';
import 'package:kotori_expense/import/default_parser.dart';
import 'package:kotori_expense/models.dart';

List<int> _sample(String name) => File('test/samples/$name').readAsBytesSync();

/// 把支付宝那份样例的表头照抄成一条自定义方式
const _copiedFromAlipay = BillRule(
  name: '照着支付宝配的',
  headers: {
    'date': '交易时间',
    'direction': '收/支',
    'amount': '金额',
    'category': '交易分类',
    'type': '收/付款方式',
    'counterparty': '交易对方',
    'item': '商品说明',
  },
);

void main() {
  test('标准 CSV：换一套列名也能解出和内置支付宝一样的结果', () {
    final bytes = _sample('alipay_sample.csv');
    final mine = parseDefault(bytes, _copiedFromAlipay)!;
    final theirs = parseAlipay(bytes)!;

    expect(mine.sourceName, '照着支付宝配的');
    expect(mine.dataRowCount, theirs.dataRowCount);
    expect(mine.txns, hasLength(theirs.txns.length));
    for (var i = 0; i < theirs.txns.length; i++) {
      expect(mine.txns[i].date, theirs.txns[i].date);
      expect(mine.txns[i].direction, theirs.txns[i].direction);
      expect(mine.txns[i].amountCents, theirs.txns[i].amountCents);
      expect(mine.txns[i].category, theirs.txns[i].category);
      expect(mine.txns[i].counterparty, theirs.txns[i].counterparty);
    }
  });

  test('列名随便叫什么都行，没配的列留空、货币补 CNY', () {
    final bytes = utf8.encode(
      '日期,摘要,对方,收支,金额\n'
      '2026-09-01 10:00:00,买菜,菜市场,支出,38.50\n'
      '2026-09-02 11:00:00,退款,超市,收入,12\n',
    );
    const rule = BillRule(
      name: '随手配',
      headers: {
        'date': '日期',
        'item': '摘要',
        'counterparty': '对方',
        'direction': '收支',
        'amount': '金额',
      },
    );

    final r = parseDefault(bytes, rule)!;
    expect(r.txns, hasLength(2));

    final first = r.txns.first;
    expect(first.date, '2026-09-01 10:00:00');
    expect(first.item, '买菜');
    expect(first.counterparty, '菜市场');
    expect(first.direction, 'expense');
    expect(first.amountCents, 3850);
    expect(first.currency, 'CNY'); // 没配货币列
    expect(first.type, isNull);
    expect(first.category, isNull);

    expect(r.txns.last.direction, 'income');
    expect(r.txns.last.amountCents, 1200);
  });

  test('xlsx 走同一条路，表头上方有标题行也找得到', () {
    final excel = Excel.createExcel();
    excel['Sheet1']
      ..appendRow([TextCellValue('工商银行交易明细')])
      ..appendRow([
        TextCellValue('日期'),
        TextCellValue('收支'),
        TextCellValue('金额'),
        TextCellValue('备注'),
      ])
      ..appendRow([
        TextCellValue('2026-09-03 08:00:00'),
        TextCellValue('支出'),
        TextCellValue('¥22.00'),
        TextCellValue('早餐'),
      ]);
    const rule = BillRule(
      name: 'xlsx 方式',
      headers: {'date': '日期', 'direction': '收支', 'amount': '金额', 'item': '备注'},
    );

    final r = parseDefault(excel.encode()!, rule)!;
    expect(r.dataRowCount, 1);
    expect(r.txns.single.amountCents, 2200);
    expect(r.txns.single.item, '早餐');
  });

  test('文件里凑不齐必需列 -> null', () {
    final bytes = utf8.encode('日期,金额\n2026-09-01,10');
    expect(parseDefault(bytes, _copiedFromAlipay), isNull);
  });

  test('规则自己就没配齐必需列 -> null', () {
    final bytes = _sample('alipay_sample.csv');
    expect(
      parseDefault(
        bytes,
        const BillRule(name: '缺金额', headers: {'date': '交易时间'}),
      ),
      isNull,
    );
  });

  test('脏行跳过并记在 issues 里，行号是表里的序号', () {
    final bytes = utf8.encode(
      '日期,收支,金额\n'
      '2026-09-01,支出,10.00\n'
      '不是日期,支出,10.00\n'
      '2026-09-03,支出,abc\n',
    );
    const rule = BillRule(
      name: 'r',
      headers: {'date': '日期', 'direction': '收支', 'amount': '金额'},
    );

    final r = parseDefault(bytes, rule)!;
    expect(r.dataRowCount, 3);
    expect(r.txns, hasLength(1));
    expect(r.skipped, 2);
    expect(r.issues.first.lineNo, 3);
    expect(r.issues.last.lineNo, 4);
  });

  test('金额带千分位 / 负号都认得，方向另算', () {
    final bytes = utf8.encode(
      '日期,收支,金额\n'
      '2026-09-01,支出,"1,299.00"\n'
      '2026-09-02,收入,-38.50\n',
    );
    const rule = BillRule(
      name: 'r',
      headers: {'date': '日期', 'direction': '收支', 'amount': '金额'},
    );

    final r = parseDefault(bytes, rule)!;
    expect(r.txns.first.amountCents, 129900);
    expect(r.txns.last.amountCents, 3850); // 负号被 abs 掉，方向看收支列
  });
}
