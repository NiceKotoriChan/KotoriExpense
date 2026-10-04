import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:fast_gbk/fast_gbk.dart';

import '../models.dart';

/// 支付宝账单的列名写死在这儿 —— 这份导出格式只有一种，不通用化。
const String _cDate = '交易时间';
const String _cDirection = '收/支';
const String _cAmount = '金额';
const String _cType = '收/付款方式';
const String _cCounterparty = '交易对方';
const String _cItem = '商品说明';
const String _cCategory = '交易分类';

/// 认表头至少要凑齐这几列，凑不齐就不是支付宝账单
const List<String> _keyColumns = [_cDate, _cDirection, _cAmount, _cItem];

/// 支付宝交易记录明细：只认 CSV（导出就是 GBK，UTF-8 也顺手认了）。
/// 金额带千分位，有分类列、没有货币列。认不出返回 null，交给下一家。
ParseResult? parseAlipay(List<int> bytes) {
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
        category: _cell(row, cols[_cCategory]),
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

/// 字节 -> CSV 二维表。先当 UTF-8 解，解不动再当 GBK；两种都不行返回 null。
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

/// '支出' -> expense，'收入' -> income；'/' 表示不计收支
String? _direction(String? raw) {
  if (raw == null) return null;
  if (raw.contains('支出')) return 'expense';
  if (raw.contains('收入')) return 'income';
  return null;
}

/// '19.00' / '1,299.00' -> 1900 / 129900
int? _cents(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$')
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
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}
