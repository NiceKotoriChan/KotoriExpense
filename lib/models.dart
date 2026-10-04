/// 一条流水，对应 entries 表的一行。
class Txn {
  /// 主键，uuidv7。新增时留空，交给 DAO 生成。
  final String? id;

  /// 交易时间，'YYYY-MM-DD HH:MM:SS'
  final String date;

  /// 交易货币，'CNY'
  final String currency;

  /// 交易类型：招行交易摘要 / 支付宝付款方式 / 微信支付方式
  final String? type;

  /// 交易对象
  final String? counterparty;

  /// 交易商品
  final String? item;

  /// 交易收支，'income' | 'expense'
  final String direction;

  /// 交易金额，单位：分，恒为正数。方向看 [direction]。
  /// 库里这一列叫 `amount`。
  final int amountCents;

  /// 交易分类，非枚举
  final String? category;

  const Txn({
    this.id,
    required this.date,
    this.currency = 'CNY',
    this.type,
    this.counterparty,
    this.item,
    required this.direction,
    required this.amountCents,
    this.category,
  });

  bool get isExpense => direction == 'expense';

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'date': date,
    'currency': currency,
    'type': type,
    'counterparty': counterparty,
    'item': item,
    'direction': direction,
    'amount': amountCents,
    'category': category,
  };

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
    id: m['id'] as String?,
    date: m['date'] as String,
    currency: (m['currency'] as String?) ?? 'CNY',
    type: m['type'] as String?,
    counterparty: m['counterparty'] as String?,
    item: m['item'] as String?,
    direction: m['direction'] as String,
    amountCents: m['amount'] as int,
    category: m['category'] as String?,
  );

  @override
  String toString() =>
      'Txn(#$id $date ${isExpense ? '-' : '+'}${formatCents(amountCents)} '
      '${counterparty ?? ''}/${item ?? ''} [${category ?? '未分类'}])';
}

/// 分 -> '¥1,299.00'
String formatCents(int cents) {
  final negative = cents < 0;
  final v = cents.abs();
  final yuan = (v ~/ 100).toString();
  final cent = (v % 100).toString().padLeft(2, '0');

  final buf = StringBuffer();
  for (var i = 0; i < yuan.length; i++) {
    if (i > 0 && (yuan.length - i) % 3 == 0) buf.write(',');
    buf.write(yuan[i]);
  }
  return '${negative ? '-' : ''}¥$buf.$cent';
}

/// '1,900.00' / '¥19' / '-19.00' -> 分；解析不了返回 null。
/// 记账页的金额输入和账单解析都走它。
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
  /// 命中的来源名；认不出来时是空串
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

/// 一条自定义解析方式，对应 rules 表的一行。
///
/// [headers] 的 key 是 entries 的列名（也是 rules 表的列名），value 是
/// 文件里的表头名 —— 也就是「把文件里的列名映射到表的列名」。
/// 没配的列不放进来；写库时补空串，因为 rules 表有几列是 NOT NULL。
class BillRule {
  final String name;
  final Map<String, String> headers;

  const BillRule({required this.name, this.headers = const {}});

  /// 编辑页的字段顺序，也是写进 rules 表的列
  static const List<String> columns = [
    'date',
    'direction',
    'amount',
    'currency',
    'type',
    'counterparty',
    'item',
    'category',
  ];

  /// 表头里凑不齐这几列就不算认出这份文件
  static const List<String> keyColumns = ['date', 'direction', 'amount'];

  static const Map<String, String> labels = {
    'date': '交易时间',
    'direction': '收支',
    'amount': '金额',
    'currency': '货币',
    'type': '交易类型',
    'counterparty': '交易对象',
    'item': '交易商品',
    'category': '分类',
  };

  /// 没配的列读回来是 null，不是空串
  String? header(String column) {
    final v = headers[column];
    return (v == null || v.isEmpty) ? null : v;
  }

  bool get isUsable => keyColumns.every((c) => header(c) != null);

  int get filledCount => columns.where((c) => header(c) != null).length;

  BillRule copyWith({String? name, Map<String, String>? headers}) =>
      BillRule(name: name ?? this.name, headers: headers ?? this.headers);

  Map<String, Object?> toRow() => {
    'name': name,
    for (final c in columns) c: headers[c] ?? '',
  };

  factory BillRule.fromRow(Map<String, Object?> row) => BillRule(
    name: row['name'] as String,
    headers: {
      for (final c in columns)
        if (((row[c] as String?) ?? '').isNotEmpty) c: row[c] as String,
    },
  );

  /// 「新规则」「新规则 2」……新建时给个不撞的默认名
  static String nextName(Iterable<String> taken) {
    const base = '新规则';
    final used = taken.toSet();
    if (!used.contains(base)) return base;
    for (var i = 2; ; i++) {
      final n = '$base $i';
      if (!used.contains(n)) return n;
    }
  }

  @override
  String toString() => 'BillRule($name, $headers)';
}
