import 'dart:convert';

/// 一条流水能从账单里取到的字段 —— 和 `transactions` 表的列一一对应。
/// 声明顺序就是映射页上的显示顺序。
enum TxnField {
  date('交易时间'),
  type('交易类型'),
  counterparty('交易对象'),
  item('交易商品'),
  currency('交易货币'),
  direction('交易收支'),
  amount('交易金额'),
  category('交易分类');

  final String label;
  const TxnField(this.label);

  static TxnField? parse(String name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// 定位表头时必须有值的字段，缺一个就认不出表头行。
/// 货币、分类这些可以整列没有，所以不算关键字段。
const List<TxnField> kKeyFields = [
  TxnField.date,
  TxnField.direction,
  TxnField.amount,
];

/// 账单里没写货币时补的值
const String kDefaultCurrency = 'CNY';

/// 一条映射规则 = 一家的账单长什么样。
///
/// [id] 是持久化用的稳定标识，改名不影响它；[name] 是页面上显示、用户能改的名字。
class BillRule {
  final String id;
  final String name;

  /// 认出「这是哪家账单」的特征列名
  final List<String> hints;

  /// 字段 -> 候选列名，按顺序试，第一个命中的赢
  final Map<TxnField, List<String>> fields;

  const BillRule({
    required this.id,
    required this.name,
    required this.hints,
    required this.fields,
  });

  List<String> headers(TxnField f) => fields[f] ?? const <String>[];

  /// 认表头至少要能定位 [kKeyFields]（时间 / 收支 / 金额），少了这条规则就废了
  bool get isUsable => kKeyFields.every((f) => headers(f).isNotEmpty);

  /// 配了几个字段（列表页上的「N 个字段」）
  int get mappedCount =>
      TxnField.values.where((f) => headers(f).isNotEmpty).length;

  BillRule copyWith({
    String? id,
    String? name,
    List<String>? hints,
    Map<TxnField, List<String>>? fields,
  }) => BillRule(
    id: id ?? this.id,
    name: name ?? this.name,
    hints: hints ?? this.hints,
    fields: fields ?? this.fields,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'hints': hints,
    'fields': {for (final f in TxnField.values) f.name: headers(f)},
  };

  /// [fallback] 用来兜住旧数据里缺的键（比如以后加了新字段）。
  /// 同 id 的出厂规则可以当兜底，用户自己加的规则传 null。
  factory BillRule.fromJson(Map<String, Object?> json, {BillRule? fallback}) {
    final id = (json['id'] ?? fallback?.id ?? '').toString();
    final rawName = json['name']?.toString();
    final name = (rawName == null || rawName.isEmpty)
        ? (fallback?.name ?? id)
        : rawName;

    final rawHints = json['hints'];
    final hints = rawHints is List
        ? rawHints.map((e) => e.toString()).toList()
        : (fallback?.hints ?? const <String>[]);

    final rawFields = json['fields'];
    final fields = <TxnField, List<String>>{};
    for (final f in TxnField.values) {
      final v = rawFields is Map ? rawFields[f.name] : null;
      fields[f] = v is List
          ? v.map((e) => e.toString()).toList()
          : (fallback?.headers(f) ?? const <String>[]);
    }
    return BillRule(id: id, name: name, hints: hints, fields: fields);
  }
}

/// 一份完整的规则集。存进 `settings` 表的 `csv_rules` 键（JSON）。
/// 谁在前谁先被拿去嗅探表头，顺序就是页面上的顺序。可以一条都没有。
class BillRules {
  final List<BillRule> rules;

  const BillRules(this.rules);

  bool get isEmpty => rules.isEmpty;

  BillRule? byId(String id) {
    for (final r in rules) {
      if (r.id == id) return r;
    }
    return null;
  }

  BillRule? byName(String name) {
    for (final r in rules) {
      if (r.name == name) return r;
    }
    return null;
  }

  /// 新增或覆盖（按 id 认），顺序保持在末尾
  BillRules upsert(BillRule rule) =>
      BillRules([for (final r in rules) if (r.id != rule.id) r, rule]);

  BillRules remove(String id) =>
      BillRules([for (final r in rules) if (r.id != id) r]);

  /// 给「新增规则」取一个没被占用的 id
  String nextId() {
    var n = rules.length + 1;
    while (byId('rule$n') != null) {
      n++;
    }
    return 'rule$n';
  }

  /// 把某条规则退回出厂值；用户自己加的规则没有出厂值，原样返回
  BillRules restoreDefault(String id) {
    final seed = kDefaultBillRules.byId(id);
    return seed == null ? this : upsert(seed);
  }

  Map<String, Object?> toJson() => {
    'rules': [for (final r in rules) r.toJson()],
  };

  String encode() => jsonEncode(toJson());

  /// 解析失败 / 缺键都落回默认值，不抛异常 —— 规则坏了不该让导入直接不能用。
  static BillRules decode(String? raw) {
    if (raw == null || raw.isEmpty) return kDefaultBillRules;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return kDefaultBillRules;

      final list = json['rules'];
      if (list is List) {
        final rules = <BillRule>[];
        final seen = <String>{};
        for (final v in list) {
          if (v is! Map) continue;
          final map = v.cast<String, Object?>();
          final id = (map['id'] ?? '').toString();
          if (id.isEmpty || !seen.add(id)) continue;
          rules.add(BillRule.fromJson(map, fallback: kDefaultBillRules.byId(id)));
        }
        // 用户可能真把规则删光了，这里不硬塞回出厂规则
        return BillRules(rules);
      }

      // 旧格式：{"alipay": {...}, "wechat": {...}} 的平铺对象，按 id 覆盖出厂规则。
      // 老版本存进去的那份还能用，不用让用户重配。
      var out = kDefaultBillRules;
      for (final e in json.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final id = e.key.toString();
        final fallback = kDefaultBillRules.byId(id);
        out = out.upsert(
          BillRule.fromJson(
            {'id': id, ...v.cast<String, Object?>()},
            fallback:
                fallback ??
                BillRule(
                  id: id,
                  name: id,
                  hints: const [],
                  fields: const {},
                ),
          ),
        );
      }
      return out;
    } catch (_) {
      return kDefaultBillRules;
    }
  }
}

/// 出厂规则。用户在设置页改了之后，数据库里的那份盖过它。
const BillRules kDefaultBillRules = BillRules([
  BillRule(
    id: 'alipay',
    name: '支付宝',
    hints: ['交易分类', '商品说明', '收/付款方式'],
    fields: {
      TxnField.date: ['交易时间', '交易创建时间'],
      TxnField.type: ['收/付款方式', '付款方式'],
      TxnField.counterparty: ['交易对方'],
      TxnField.item: ['商品说明', '商品名称'],
      TxnField.direction: ['收/支', '收支'],
      TxnField.amount: ['金额', '金额（元）', '金额(元)'],
      TxnField.category: ['交易分类'],
    },
  ),
  BillRule(
    id: 'wechat',
    name: '微信',
    hints: ['支付方式', '当前状态', '商户单号'],
    fields: {
      TxnField.date: ['交易时间'],
      TxnField.type: ['支付方式'],
      TxnField.counterparty: ['交易对方'],
      TxnField.item: ['商品'],
      TxnField.direction: ['收/支', '收支'],
      TxnField.amount: ['金额(元)', '金额（元）', '金额'],
      // 微信账单没有分类列
      TxnField.category: [],
    },
  ),
  BillRule(
    id: 'cmb',
    name: '招商银行',
    // 这两列名是招行独有的，拿来当特征列
    hints: ['交易摘要', '记账日期'],
    fields: {
      TxnField.date: ['记账日期', '交易日期', '交易时间'],
      // 招行的「交易摘要」是消费说明，正好当交易类型
      TxnField.type: ['交易摘要', '交易类型'],
      TxnField.counterparty: ['交易对方', '对手信息'],
      TxnField.item: ['交易备注', '备注'],
      TxnField.currency: ['货币', '币种'],
      TxnField.direction: ['收支标志', '交易方向', '收/支', '收支'],
      TxnField.amount: [
        '交易金额（元）',
        '交易金额(元)',
        '人民币金额',
        '交易金额',
        '金额',
      ],
      // 招行账单没有分类列
      TxnField.category: [],
    },
  ),
]);
