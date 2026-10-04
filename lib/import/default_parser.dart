import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:fast_gbk/fast_gbk.dart';

import '../models.dart';

/// 用户自定义的解析方式：照 [rule] 的列名映射去读标准的 CSV / XLSX。
/// 表头里凑不齐 rule 要的那几列，就返回 null、交给调用方报错。
ParseResult? parseDefault(List<int> bytes, BillRule rule) {
  if (!rule.isUsable) return null;

  final rows = _rows(bytes);
  if (rows == null) return null;

  final head = _findHeader(rows, rule);
  if (head < 0) return null;
  final cols = {
    for (var i = 0; i < rows[head].length; i++)
      rows[head][i].toString().trim(): i,
  };

  /// 按「表的列名」取这一行的值
  String? at(List<dynamic> row, String column) {
    final name = rule.header(column);
    final i = name == null ? null : cols[name];
    if (i == null || i >= row.length) return null;
    final v = row[i]?.toString().trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  final txns = <Txn>[];
  final issues = <ParseIssue>[];
  var dataRows = 0;

  for (var i = head + 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.every((c) => c.toString().trim().isEmpty)) continue;
    dataRows++;

    final date = _date(at(row, 'date'));
    if (date == null) {
      issues.add(ParseIssue(i + 1, '交易时间缺失或认不出格式'));
      continue;
    }

    final direction = _direction(at(row, 'direction'));
    if (direction == null) {
      issues.add(ParseIssue(i + 1, '收支认不出'));
      continue;
    }

    final cents = parseAmountCents(at(row, 'amount'))?.abs();
    if (cents == null || cents == 0) {
      issues.add(ParseIssue(i + 1, '金额认不出或为 0'));
      continue;
    }

    txns.add(
      Txn(
        date: date,
        direction: direction,
        amountCents: cents,
        currency: at(row, 'currency') ?? 'CNY',
        type: at(row, 'type'),
        counterparty: at(row, 'counterparty'),
        item: at(row, 'item'),
        category: at(row, 'category'),
      ),
    );
  }

  return ParseResult(
    sourceName: rule.name,
    txns: txns,
    issues: issues,
    dataRowCount: dataRows,
  );
}

/// 字节 -> 二维表。xlsx 是个 zip，头两个字节固定是 'PK'；其余按 CSV 文本读，
/// 先当 UTF-8 解，解不动再当 GBK。都读不出来返回 null。
List<List<dynamic>>? _rows(List<int> bytes) {
  if (bytes.length > 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
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

String _cellText(Data? cell) => cell?.value?.toString() ?? '';

int _findHeader(List<List<dynamic>> rows, BillRule rule) {
  final limit = rows.length < 40 ? rows.length : 40;
  final want = [for (final c in BillRule.keyColumns) rule.header(c) ?? ''];
  for (var i = 0; i < limit; i++) {
    final cells = rows[i].map((c) => c.toString().trim()).toSet();
    if (want.every(cells.contains)) return i;
  }
  return -1;
}

/// '支出' -> expense，'收入' -> income；抄来的英文表也认
String? _direction(String? raw) {
  if (raw == null) return null;
  final lower = raw.toLowerCase();
  if (raw.contains('支出') || lower == 'expense') return 'expense';
  if (raw.contains('收入') || lower == 'income') return 'income';
  return null;
}

String? _date(String? raw) {
  if (raw == null) return null;
  final d = DateTime.tryParse(raw);
  if (d == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}
