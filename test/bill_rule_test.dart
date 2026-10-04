import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/models.dart';

void main() {
  const icbc = BillRule(
    name: '工行',
    headers: {
      'date': '交易日期',
      'direction': '借贷标志',
      'amount': '交易金额',
      'item': '摘要',
    },
  );

  group('BillRule', () {
    test('没配的列读回来是 null，不是空串', () {
      expect(icbc.header('counterparty'), isNull);
      expect(icbc.header('category'), isNull);
      expect(icbc.header('date'), '交易日期');
    });

    test('必需列齐了才 isUsable', () {
      expect(icbc.isUsable, isTrue);
      expect(
        const BillRule(
          name: '缺金额',
          headers: {'date': '日期', 'direction': '收支'},
        ).isUsable,
        isFalse,
      );
    });

    test('写库时没配的列补空串 —— rules 表有几列是 NOT NULL', () {
      final row = icbc.toRow();
      expect(row.length, BillRule.columns.length + 1); // + name
      expect(row['name'], '工行');
      for (final c in BillRule.columns) {
        expect(row[c], isA<String>());
      }
      expect(row['category'], '');
    });

    test('往返一趟不丢东西', () {
      final back = BillRule.fromRow(icbc.toRow());
      expect(back.name, '工行');
      expect(back.headers, icbc.headers);
    });

    test('空串当没配，不进 headers', () {
      final back = BillRule.fromRow({...icbc.toRow(), 'category': ''});
      expect(back.headers.containsKey('category'), isFalse);
    });

    test('列名跟 rules 表的列一一对上', () {
      expect(BillRule.columns, [
        'date',
        'direction',
        'amount',
        'currency',
        'type',
        'counterparty',
        'item',
        'category',
      ]);
      expect(BillRule.keyColumns, ['date', 'direction', 'amount']);
      for (final c in BillRule.columns) {
        expect(BillRule.labels[c], isNotNull);
      }
    });

    test('filledCount 数配了几列', () {
      expect(icbc.filledCount, 4);
      expect(const BillRule(name: '空').filledCount, 0);
    });

    test('copyWith 不会动原对象', () {
      final r = icbc.copyWith(
        name: '工行储蓄卡',
        headers: {...icbc.headers, 'category': '分类'},
      );
      expect(r.name, '工行储蓄卡');
      expect(r.header('category'), '分类');
      expect(icbc.header('category'), isNull);
    });

    test('新建时给个不撞的默认名', () {
      expect(BillRule.nextName(const []), '新规则');
      expect(BillRule.nextName(const ['新规则']), '新规则 2');
      expect(BillRule.nextName(const ['新规则', '新规则 2']), '新规则 3');
      expect(BillRule.nextName(const ['别的', '新规则 2']), '新规则');
    });
  });
}
