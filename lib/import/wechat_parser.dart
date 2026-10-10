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

  final head = _findHeader(rows);
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

    final date = _date(_cell(row, cols[_cDate]));
    if (date == null) {
      issues.add(ParseIssue(i + 1, '交易时间缺失或认不出格式'));
      continue;
    }

    final dirRaw = _cell(row, cols[_cDirection]);
    final direction = _direction(dirRaw);
    if (direction == null) {
      issues.add(ParseIssue(i + 1, '收支为「${dirRaw ?? '空'}」，不计入收支'));
      continue;
    }

    final cents = _cents(_cell(row, cols[_cAmount]));
    if (cents == null) {
      issues.add(ParseIssue(i + 1, '金额认不出或为 0'));
      continue;
    }

    txns.add(
      Txn(
        date: date,
        direction: direction,
        amountCents: cents,
        type: _cell(row, cols[_cType]),
        counterparty: _cell(row, cols[_cCounterparty]),
        item: _cell(row, cols[_cItem]),
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

int _findHeader(List<List<dynamic>> rows) {
  final limit = rows.length < 40 ? rows.length : 40;
  for (var i = 0; i < limit; i++) {
    final cells = rows[i].map((c) => c.toString().trim()).toSet();
    if (_keyColumns.every(cells.contains)) return i;
  }
  return -1;
}

String? _cell(List<dynamic> row, int? index) {
  if (index == null || index >= row.length) return null;
  final v = row[index]?.toString().trim();
  return (v == null || v.isEmpty) ? null : v;
}

String? _direction(String? raw) {
  if (raw == null) return null;
  if (raw.contains('支出')) return 'expense';
  if (raw.contains('收入')) return 'income';
  return null;
}

int? _cents(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^[¥￥]?\s*(\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(raw.replaceAll(',', '').trim());
  if (m == null) return null;
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final cents = int.parse(m.group(1)!) * 100 + int.parse(frac);
  return cents == 0 ? null : cents;
}

String? _date(String? raw) {
  if (raw == null) return null;
  final d = DateTime.tryParse(raw);
  if (d == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}
