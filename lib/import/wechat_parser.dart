import 'package:excel/excel.dart';

import '../models.dart';

const String _cDate = '交易时间';
const String _cDirection = '收/支';
const String _cAmount = '金额(元)';
const String _cType = '支付方式';
const String _cCounterparty = '交易对方';
const String _cItem = '商品';

const List<String> _keyColumns = [_cDate, _cDirection, _cAmount];

ParseResult? parseWechat(List<int> bytes) {
  final rows = _rows(bytes);
  if (rows == null) return null;

  final head = findHeaderRow(rows, _keyColumns);
  if (head < 0) return null;
  final cols = {
    for (var i = 0; i < rows[head].length; i++)
      rows[head][i].toString().trim(): i,
  };

  final txns = <Txn>[];
  final issues = <ParseIssue>[];
  var dataRows = 0;

  for (var i = head + 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.every((c) => c.toString().trim().isEmpty)) continue;
    dataRows++;

    final date = isoDay(cellAt(row, cols[_cDate]));
    if (date == null) {
      issues.add(ParseIssue(i + 1, '交易时间缺失或认不出格式'));
      continue;
    }

    final dirRaw = cellAt(row, cols[_cDirection]);
    final direction = directionOf(dirRaw);
    if (direction == null) {
      issues.add(ParseIssue(i + 1, '收支为「${dirRaw ?? '空'}」，不计入收支'));
      continue;
    }

    final cents = _cents(cellAt(row, cols[_cAmount]));
    if (cents == null) {
      issues.add(ParseIssue(i + 1, '金额认不出或为 0'));
      continue;
    }

    txns.add(
      Txn(
        date: date,
        direction: direction,
        amountCents: cents,
        type: cellAt(row, cols[_cType]),
        counterparty: cellAt(row, cols[_cCounterparty]),
        item: cellAt(row, cols[_cItem]),
      ),
    );
  }

  return ParseResult(
    sourceName: '微信',
    txns: txns,
    issues: issues,
    dataRowCount: dataRows,
  );
}

List<List<dynamic>>? _rows(List<int> bytes) {
  if (bytes.length <= 2 || bytes[0] != 0x50 || bytes[1] != 0x4B) return null;
  try {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) return null;
    return [
      for (final row in book.tables.values.first.rows)
        [for (final cell in row) _cellText(cell)],
    ];
  } catch (_) {
    return null;
  }
}

String _cellText(Data? cell) => cell?.value?.toString() ?? '';

int? _cents(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^[¥￥]?\s*(\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(raw.replaceAll(',', '').trim());
  if (m == null) return null;
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final cents = int.parse(m.group(1)!) * 100 + int.parse(frac);
  return cents == 0 ? null : cents;
}
