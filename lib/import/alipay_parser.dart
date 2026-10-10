import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:fast_gbk/fast_gbk.dart';

import '../models.dart';

const String _cDate = '交易时间';
const String _cDirection = '收/支';
const String _cAmount = '金额';
const String _cType = '收/付款方式';
const String _cCounterparty = '交易对方';
const String _cItem = '商品说明';
const String _cCategory = '交易分类';

const List<String> _keyColumns = [_cDate, _cDirection, _cAmount, _cItem];

ParseResult? parseAlipay(List<int> bytes) {
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
        category: cellAt(row, cols[_cCategory]),
      ),
    );
  }

  return ParseResult(
    sourceName: '支付宝',
    txns: txns,
    issues: issues,
    dataRowCount: dataRows,
  );
}

List<List<dynamic>>? _rows(List<int> bytes) {
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    try {
      text = gbk.decode(bytes);
    } on FormatException {
      return null;
    }
  }
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  return Csv(autoDetect: true).decode(text);
}

int? _cents(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(raw.replaceAll(',', '').trim());
  if (m == null) return null;
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final cents = int.parse(m.group(1)!) * 100 + int.parse(frac);
  return cents == 0 ? null : cents;
}
