import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:fast_gbk/fast_gbk.dart';

import '../models.dart';
import 'mapping_rules.dart';

export 'mapping_rules.dart'
    show
        BillRule,
        TxnField,
        BillRules,
        kDefaultBillRules,
        kDefaultCurrency,
        kKeyFields;

/// 某一行没被采用的原因
class ParseIssue {
  final int lineNo;
  final String reason;

  const ParseIssue(this.lineNo, this.reason);

  @override
  String toString() => '第 $lineNo 行：$reason';
}

/// 一次解析的结果
class ParseResult {
  /// 命中的规则名；认不出来时是空串
  final String sourceName;

  final List<Txn> txns;
  final List<ParseIssue> issues;

  /// 表头之后的数据行数（含被跳过的）
  final int dataRowCount;

  const ParseResult({
    required this.sourceName,
    required this.txns,
    required this.issues,
    required this.dataRowCount,
  });

  int get skipped => issues.length;

  @override
  String toString() =>
      '${sourceName.isEmpty ? '未知来源' : sourceName}：'
      '解析 ${txns.length} 条，跳过 $skipped 条（共 $dataRowCount 数据行）';
}

// ---------------------------------------------------------------- 基础工具

/// 去掉 UTF-8 BOM
String stripBom(String s) => s.startsWith('\uFEFF') ? s.substring(1) : s;

/// 账单解码：优先 UTF-8，失败退回 GBK。
/// 微信导出一般是 UTF-8，支付宝导出常是 GBK（直接当 UTF-8 读会乱码）。
String decodeBillBytes(List<int> bytes) {
  try {
    return stripBom(utf8.decode(bytes));
  } on FormatException {
    return stripBom(gbk.decode(bytes));
  }
}

/// CSV / TSV 文本 -> 二维表。
/// 换行符 \r\n 与 \n 混用、逗号还是制表符，都交给 autoDetect。
/// 不把数字转成 num —— 否则订单号会丢精度、丢前导零。
List<List<dynamic>> parseCsvRows(String text, {String? fieldDelimiter}) {
  if (fieldDelimiter != null) {
    return Csv(fieldDelimiter: fieldDelimiter, autoDetect: false).decode(text);
  }
  return Csv(autoDetect: true).decode(text);
}

/// 在前 80 行里找表头行下标，找不到返回 -1。
///
/// [groups] 是「每一组里命中任意一个即可」的候选列名，
/// 因为同一列在不同版本的账单里叫法不同（金额 / 金额(元) / 金额（元））。
int findHeaderRow(List<List<dynamic>> rows, List<List<String>> groups) {
  final limit = rows.length < 80 ? rows.length : 80;
  for (var i = 0; i < limit; i++) {
    final cells = rows[i].map((c) => c.toString().trim()).toSet();
    if (groups.every((g) => g.any(cells.contains))) return i;
  }
  return -1;
}

/// '1,900.00' / '¥19' / '-19.00' -> 分；解析不了返回 null
int? parseAmountCents(String? raw) {
  if (raw == null) return null;
  var s = raw
      .replaceAll('¥', '')
      .replaceAll('￥', '')
      .replaceAll(',', '')
      .replaceAll('，', '')
      .replaceAll(' ', '')
      .trim();
  if (s.isEmpty || s == '/') return null;

  var negative = false;
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }

  final dot = s.indexOf('.');
  final intPart = dot < 0 ? s : s.substring(0, dot);
  var fracPart = dot < 0 ? '' : s.substring(dot + 1);
  if (!RegExp(r'^\d+$').hasMatch(intPart)) return null;
  if (fracPart.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fracPart)) return null;

  fracPart = '${fracPart}00'.substring(0, 2); // 不足补 0，超出截断
  final cents = int.parse(intPart) * 100 + int.parse(fracPart);
  return negative ? -cents : cents;
}

/// 各种日期写法 -> 'YYYY-MM-DD HH:MM:SS'；解析不了返回 null。
/// 只有日期没有时间的，时间补 00:00:00。
String? normalizeDateTime(String? raw) {
  if (raw == null) return null;
  final s = raw.trim().replaceAll('/', '-').replaceAll('.', '-');
  final m = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?',
  ).firstMatch(s);
  if (m == null) return null;
  final y = m.group(1)!;
  final mo = m.group(2)!.padLeft(2, '0');
  final d = m.group(3)!.padLeft(2, '0');
  final hh = (m.group(4) ?? '0').padLeft(2, '0');
  final mi = (m.group(5) ?? '0').padLeft(2, '0');
  final ss = (m.group(6) ?? '0').padLeft(2, '0');
  return '$y-$mo-$d $hh:$mi:$ss';
}

/// 货币列的别名。靠前的先匹配，所以「美元」必须排在「元」前面。
const Map<String, String> _currencyAliases = {
  '人民币': 'CNY',
  '美元': 'USD',
  '美金': 'USD',
  '港币': 'HKD',
  '港元': 'HKD',
  '欧元': 'EUR',
  '日元': 'JPY',
  '英镑': 'GBP',
  '元': 'CNY',
  '￥': 'CNY',
  '¥': 'CNY',
};

/// 货币列 -> 三字母代码。认不出、或者账单根本没有这一列，都按 CNY。
String normalizeCurrency(String? raw) {
  if (raw == null) return kDefaultCurrency;
  final s = raw.trim();
  if (s.isEmpty) return kDefaultCurrency;

  final upper = s.toUpperCase();
  if (RegExp(r'^[A-Z]{3}$').hasMatch(upper)) return upper;
  for (final e in _currencyAliases.entries) {
    if (s.contains(e.key)) return e.value;
  }
  return kDefaultCurrency;
}

/// '支出'/'收入' -> 'expense'/'income'
/// 微信账单里的 '/' 表示「不计收支」（提现、转账之类），返回 null 由上层跳过。
String? parseDirection(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty || s == '/' || s == '\\' || s.contains('不计')) return null;
  if (s.contains('支出') || s == '支') return 'expense';
  if (s.contains('收入') || s == '收') return 'income';
  return null;
}

// ---------------------------------------------------------------- 表头索引

/// 列名 -> 列下标
class HeaderIndex {
  final List<String> cells;

  const HeaderIndex(this.cells);

  static HeaderIndex of(List<dynamic> row) =>
      HeaderIndex(row.map((c) => c.toString().trim()).toList());

  int? indexOfAny(List<String> candidates) {
    for (final c in candidates) {
      final i = cells.indexOf(c);
      if (i >= 0) return i;
    }
    return null;
  }

  /// 取单元格，空串视为 null
  String? value(List<dynamic> row, List<String> candidates) {
    final i = indexOfAny(candidates);
    if (i == null || i >= row.length) return null;
    final v = row[i]?.toString().trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}

// ---------------------------------------------------------------- 单行结果

class _RowResult {
  final Txn? txn;
  final String? reason;

  const _RowResult.ok(this.txn) : reason = null;
  const _RowResult.skip(this.reason) : txn = null;
}

// ---------------------------------------------------------------- 来源嗅探

/// 靠表头列名认规则，比匹配「支付宝」三个字可靠
/// （账单正文里也可能提到对方平台的付款方式）。认不出返回 null。
BillRule? sniffRule(
  List<List<dynamic>> rows, [
  BillRules rules = kDefaultBillRules,
]) {
  final limit = rows.length < 40 ? rows.length : 40;

  for (var i = 0; i < limit; i++) {
    final cells = rows[i].map((c) => c.toString().trim()).toSet();
    for (final r in rules.rules) {
      if (r.hints.any(cells.contains)) return r;
    }
  }

  // 表头认不出来，退一步在正文里找规则名。规则改了名也跟着变。
  final head = rows
      .take(limit)
      .expand((r) => r)
      .map((c) => c.toString())
      .join(' ');
  for (final r in rules.rules) {
    if (r.name.isNotEmpty && head.contains(r.name)) return r;
  }
  return null;
}

// ---------------------------------------------------------------- 解析主体

/// 按某条规则解析整张表
ParseResult parseByRules(List<List<dynamic>> rows, BillRule rule) {
  final groups = [for (final f in kKeyFields) rule.headers(f)];

  final headerRow = findHeaderRow(rows, groups);
  if (headerRow < 0) {
    final need = kKeyFields
        .map((f) => rule.headers(f).isEmpty ? f.label : rule.headers(f).first)
        .join(' / ');
    return ParseResult(
      sourceName: rule.name,
      txns: const [],
      dataRowCount: 0,
      issues: [ParseIssue(0, '找不到表头行（需要包含 $need）')],
    );
  }

  final h = HeaderIndex.of(rows[headerRow]);
  final txns = <Txn>[];
  final issues = <ParseIssue>[];
  var dataRows = 0;

  for (var i = headerRow + 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.every((c) => c.toString().trim().isEmpty)) continue; // 空行
    dataRows++;
    final res = _buildRow(h, row, rule);
    final txn = res.txn;
    if (txn != null) {
      txns.add(txn);
    } else {
      issues.add(ParseIssue(i + 1, res.reason ?? '无法解析'));
    }
  }

  return ParseResult(
    sourceName: rule.name,
    txns: txns,
    issues: issues,
    dataRowCount: dataRows,
  );
}

_RowResult _buildRow(HeaderIndex h, List<dynamic> row, BillRule r) {
  final date = normalizeDateTime(h.value(row, r.headers(TxnField.date)));
  if (date == null) return const _RowResult.skip('交易时间缺失或认不出格式');

  final dirRaw = h.value(row, r.headers(TxnField.direction));
  final dir = parseDirection(dirRaw);
  if (dir == null) {
    return _RowResult.skip('收支为「${dirRaw ?? '空'}」，不计入收支');
  }

  final amountRaw = h.value(row, r.headers(TxnField.amount));
  final amt = parseAmountCents(amountRaw);
  if (amt == null || amt == 0) {
    return _RowResult.skip('金额认不出或为 0：$amountRaw');
  }

  return _RowResult.ok(
    Txn(
      date: date,
      currency: normalizeCurrency(h.value(row, r.headers(TxnField.currency))),
      direction: dir,
      amountCents: amt.abs(),
      type: h.value(row, r.headers(TxnField.type)),
      counterparty: h.value(row, r.headers(TxnField.counterparty)),
      item: h.value(row, r.headers(TxnField.item)),
      category: h.value(row, r.headers(TxnField.category)),
    ),
  );
}

// ---------------------------------------------------------------- 入口

/// 入口：认规则 + 分发。xlsx 解出来的二维表也走这里。
ParseResult parseBillRows(
  List<List<dynamic>> rows, [
  BillRules rules = kDefaultBillRules,
]) {
  final rule = sniffRule(rows, rules);
  if (rule == null) {
    return ParseResult(
      sourceName: '',
      txns: const [],
      dataRowCount: 0,
      issues: [ParseIssue(0, _unknownHint(rules))],
    );
  }
  return parseByRules(rows, rule);
}

String _unknownHint(BillRules rules) {
  if (rules.isEmpty) {
    return '认不出是哪家的账单：现在一条映射规则都没有，先去设置里加一条';
  }
  final names = rules.rules.map((r) => r.name).join('、');
  return '认不出是哪家的账单（现有规则：$names，表头都没命中特征列）';
}

/// 入口：CSV / TSV 文本（分隔符由 autoDetect 判断）
ParseResult parseBillText(String text, [BillRules rules = kDefaultBillRules]) =>
    parseBillRows(parseCsvRows(stripBom(text)), rules);

/// 跳过嗅探，直接拿指定 id 的规则解析（测试、以及以后做「手动指定来源」用）
ParseResult parseRowsAs(
  List<List<dynamic>> rows,
  String ruleId, [
  BillRules rules = kDefaultBillRules,
]) {
  final rule = rules.byId(ruleId);
  if (rule == null) {
    return ParseResult(
      sourceName: '',
      txns: const [],
      dataRowCount: 0,
      issues: [ParseIssue(0, '没有 id 为「$ruleId」的映射规则')],
    );
  }
  return parseByRules(rows, rule);
}

ParseResult parseTextAs(
  String text,
  String ruleId, [
  BillRules rules = kDefaultBillRules,
]) => parseRowsAs(parseCsvRows(stripBom(text)), ruleId, rules);

/// xlsx 本质是个 zip，头两个字节固定是 'PK'
bool looksLikeXlsx(List<int> bytes) =>
    bytes.length > 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;

/// 取 xlsx 的第一个 sheet 转成二维表
List<List<dynamic>> readXlsxRows(List<int> bytes) {
  final book = Excel.decodeBytes(bytes);
  if (book.tables.isEmpty) return const [];
  final sheet = book.tables.values.first;
  return sheet.rows.map((row) => row.map(_cellText).toList()).toList();
}

String _cellText(Data? cell) {
  final v = cell?.value;
  if (v == null) return '';
  return switch (v) {
    TextCellValue(value: final s) => s.toString(),
    _ => v.toString(),
  };
}

/// 入口（字节版）：CSV 自动处理 UTF-8 / GBK，xlsx 走 zip 分支
ParseResult parseBillBytes(
  List<int> bytes, [
  BillRules rules = kDefaultBillRules,
]) => looksLikeXlsx(bytes)
    ? parseBillRows(readXlsxRows(bytes), rules)
    : parseBillText(decodeBillBytes(bytes), rules);
