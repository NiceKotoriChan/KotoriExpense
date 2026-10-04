import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import 'import/mapping_rules.dart';
import 'models.dart';

/// 与 docs/schema.sql 一致（docs 里那版末尾多了个逗号，跑不了，这里是修好的）。
const String kCreateTableSql = '''
CREATE TABLE IF NOT EXISTS transactions (
    id              TEXT    PRIMARY KEY,
    date            TEXT    NOT NULL,
    currency        TEXT    NOT NULL DEFAULT 'CNY',
    type            TEXT,
    counterparty    TEXT,
    item            TEXT,
    direction       TEXT    NOT NULL CHECK (direction IN ('income', 'expense')),
    cents           INTEGER NOT NULL CHECK (cents > 0),
    category        TEXT
)
''';

/// 交易分类和 ICON 的映射
const String kCreateCategoryIconSql = '''
CREATE TABLE IF NOT EXISTS category_icon (
    category  TEXT PRIMARY KEY,
    icon TEXT NOT NULL
)
''';

/// 映射 SQL 的数据字段
const String kCreateSettingsSql = '''
CREATE TABLE IF NOT EXISTS settings (
    name  TEXT PRIMARY KEY,
    date  TEXT NOT NULL,
    currency  TEXT,
    type  TEXT,
    counterparty  TEXT NOT NULL,
    item  TEXT NOT NULL,
    direction  TEXT NOT NULL,
    cents  TEXT NOT NULL
    category  TEXT
)
''';

/// `settings` 表里存 CSV 映射规则用的键
const String kCsvRulesKey = 'csv_rules';

/// 建库时灌进 `category_icon` 的初始数据。之后一切以数据库为准，
/// 这份常量只在「表还是空的时候」用一次。
const Map<String, String> kDefaultCategoryIcons = {
  '餐饮美食': 'restaurant',
  '日用百货': 'shopping_basket',
  '交通出行': 'directions_car',
  '数码电器': 'devices',
  '服饰装扮': 'checkroom',
  '美容美发': 'content_cut',
  '生活服务': 'home_repair_service',
  '医疗健康': 'medical_services',
  '文化休闲': 'local_activity',
  '教育培训': 'school',
  '住房物业': 'home',
  '投资理财': 'savings',
  '保险': 'health_and_safety',
  '充值缴费': 'payments',
  '转账': 'swap_horiz',
  '红包': 'redeem',
  '商业服务': 'business_center',
  '亲友代付': 'group',
  '宠物': 'pets',
  '运动户外': 'fitness_center',
  '旅行住宿': 'flight',
  '其他': 'more_horiz',
};

/// 分类名 -> 图标名。
///
/// 先精确查，再退一步做包含匹配 —— 账单里的分类名常带后缀（「餐饮美食类」）。
/// 认不出返回 null，交给 AppIcons.resolve 兜底。
String? iconNameForCategory(String? category, Map<String, String> mapping) {
  if (category == null || category.isEmpty) return null;
  final exact = mapping[category];
  if (exact != null) return exact;
  for (final e in mapping.entries) {
    if (category.contains(e.key)) return e.value;
  }
  return null;
}

class Summary {
  final int incomeCents;
  final int expenseCents;
  final int count;

  const Summary({
    required this.incomeCents,
    required this.expenseCents,
    required this.count,
  });

  int get netCents => incomeCents - expenseCents;
}

/// [factory] 由调用方注入：App 传 `sqflite.databaseFactory`，测试传
/// `databaseFactoryFfi`，这样本文件不绑 Flutter，纯 Dart 也能验 SQL。
Future<Database> openAppDb({
  required DatabaseFactory factory,
  String? path,
}) async {
  final dbPath =
      path ?? p.join(await factory.getDatabasesPath(), 'kotori_expense.db');
  return factory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: 4,
      onCreate: (db, _) async {
        await db.execute(kCreateTableSql);
        await db.execute(kCreateCategoryIconSql);
        await db.execute(kCreateSettingsSql);
        await _seedCategoryIcons(db);
      },
      onUpgrade: (db, from, _) async {
        if (from < 2) await db.execute(kCreateCategoryIconSql);
        if (from < 3) await _seedCategoryIcons(db);
        if (from < 4) await db.execute(kCreateSettingsSql);
      },
    ),
  );
}

/// 表为空时才灌初始数据。用户改过 / 删过就不动他。
Future<void> _seedCategoryIcons(Database db) async {
  final r = await db.rawQuery('SELECT COUNT(*) AS c FROM category_icon');
  if (((r.first['c'] as int?) ?? 0) > 0) return;
  final batch = db.batch();
  kDefaultCategoryIcons.forEach((category, iconName) {
    batch.insert('category_icon', {
      'category': category,
      'icon_name': iconName,
    });
  });
  await batch.commit(noResult: true);
}

class TxnDao {
  final Database db;

  TxnDao(this.db);

  Future<int> insert(Txn t) => db.insert('transactions', t.toMap());

  Future<int> update(Txn t) {
    final id = t.id;
    if (id == null) throw ArgumentError('要更新的流水没有 id');
    return db.update(
      'transactions',
      t.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTxn(int id) =>
      db.delete('transactions', where: 'id = ?', whereArgs: [id]);

  Future<Txn?> findById(int id) async {
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Txn.fromMap(rows.first);
  }

  /// 记过的分类 + category_icon 里配置过的分类。录入时给下拉建议用。
  Future<List<String>> knownCategories() async {
    final rows = await db.rawQuery('''
      SELECT DISTINCT category AS c FROM transactions
        WHERE category IS NOT NULL AND category <> ''
      UNION
      SELECT category AS c FROM category_icon
    ''');
    return [for (final r in rows) r['c'] as String]..sort();
  }

  /// 关键词搜索：交易对象 / 商品 / 分类 / 类型，任意一个含关键词就算命中。
  Future<List<Txn>> search(String keyword, {int limit = 300}) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];
    // % 和 _ 在 LIKE 里是通配符，用户真输这两个字符时要当字面量看
    final escaped = kw
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final like = '%$escaped%';

    final rows = await db.query(
      'transactions',
      where:
          "(counterparty LIKE ? ESCAPE '\\' OR "
          "item LIKE ? ESCAPE '\\' OR "
          "category LIKE ? ESCAPE '\\' OR "
          "type LIKE ? ESCAPE '\\')",
      whereArgs: [like, like, like, like],
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return rows.map(Txn.fromMap).toList();
  }

  /// 批量写入，包在一个事务里。要么全成，要么抛异常。
  Future<int> insertAll(Iterable<Txn> txns) async {
    final items = txns.toList();
    if (items.isEmpty) return 0;
    final batch = db.batch();
    for (final t in items) {
      batch.insert('transactions', t.toMap());
    }
    await batch.commit(noResult: true);
    return items.length;
  }

  Future<List<Txn>> listAll({int? limit}) async {
    final rows = await db.query(
      'transactions',
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<int> count() async {
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM transactions');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<Summary> summary() async {
    final r = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN direction = 'income'  THEN amount_cents END), 0) AS income,
        COALESCE(SUM(CASE WHEN direction = 'expense' THEN amount_cents END), 0) AS expense,
        COUNT(*) AS cnt
      FROM transactions
    ''');
    final row = r.first;
    return Summary(
      incomeCents: (row['income'] as int?) ?? 0,
      expenseCents: (row['expense'] as int?) ?? 0,
      count: (row['cnt'] as int?) ?? 0,
    );
  }

  Future<void> deleteAll() => db.delete('transactions');

  /// 整张分类映射表，带初始数据。页面加载一次即可。
  Future<Map<String, String>> categoryIcons() async {
    final rows = await db.query('category_icon');
    return {
      for (final r in rows) r['category'] as String: r['icon_name'] as String,
    };
  }

  /// [iconName] 必须是 `AppIcons.choices` 里的名字。
  Future<void> setCategoryIcon(String category, String iconName) async {
    await db.insert('category_icon', {
      'category': category,
      'icon_name': iconName,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 恢复初始值；不在初始表里的分类直接删掉。
  Future<void> resetCategoryIcon(String category) async {
    final fallback = kDefaultCategoryIcons[category];
    if (fallback == null) {
      await db.delete(
        'category_icon',
        where: 'category = ?',
        whereArgs: [category],
      );
    } else {
      await setCategoryIcon(category, fallback);
    }
  }

  // ────────────────────────────────────────── 杂项配置

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) => db.insert('settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> removeSetting(String key) =>
      db.delete('settings', where: 'key = ?', whereArgs: [key]);

  /// 用户在设置页改过的 CSV 映射；没改过就是出厂规则。
  Future<BillRules> csvRules() async =>
      BillRules.decode(await setting(kCsvRulesKey));

  Future<void> saveCsvRules(BillRules rules) =>
      setSetting(kCsvRulesKey, rules.encode());

  Future<void> resetCsvRules() => removeSetting(kCsvRulesKey);

  // ────────────────────────────────────────── 日期区间

  /// [from] / [to] 是 'YYYY-MM-DD'，两端都含。
  /// date 列是 'YYYY-MM-DD HH:MM:SS'，字符串比较即可正确排序。
  Future<List<Txn>> listRange(String from, String to) async {
    final rows = await db.query(
      'transactions',
      where: 'date >= ? AND date <= ?',
      whereArgs: ['$from 00:00:00', '$to 23:59:59'],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }
}
