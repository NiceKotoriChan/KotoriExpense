class Txn {
  final String? id;
  final int? recordId;
  final String date;
  final String currency;
  final String? type;
  final String? counterparty;
  final String? item;
  final String direction;
  final int amountCents;
  final String? category;

  const Txn({
    this.id,
    this.recordId,
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
    recordId: m['record'] as int?,
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

  fracPart = '${fracPart}00'.substring(0, 2);
  final cents = int.parse(intPart) * 100 + int.parse(fracPart);
  return negative ? -cents : cents;
}

class ParseIssue {
  final int lineNo;
  final String reason;

  const ParseIssue(this.lineNo, this.reason);

  @override
  String toString() => '第 $lineNo 行：$reason';
}

class ParseResult {
  final String sourceName;
  final List<Txn> txns;
  final List<ParseIssue> issues;
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
