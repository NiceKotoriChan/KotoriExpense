/// 一条流水，对应 transactions 表的一行。
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
  /// 库里这一列叫 `cents`。
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

  /// 金额展示，分 -> '19.00'
  String get amountText {
    final yuan = amountCents ~/ 100;
    final cent = (amountCents % 100).toString().padLeft(2, '0');
    return '$yuan.$cent';
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'date': date,
    'currency': currency,
    'type': type,
    'counterparty': counterparty,
    'item': item,
    'direction': direction,
    'cents': amountCents,
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
    amountCents: m['cents'] as int,
    category: m['category'] as String?,
  );

  @override
  String toString() =>
      'Txn(#$id $date ${isExpense ? '-' : '+'}$amountText '
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
