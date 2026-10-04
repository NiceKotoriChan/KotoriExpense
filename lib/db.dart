import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const String kCreateSqlEntries = '''
CREATE TABLE IF NOT EXISTS entries (
    id              TEXT    PRIMARY KEY,
    date            TEXT    NOT NULL,
    type            TEXT,
    counterparty    TEXT,
    item            TEXT,
    currency        TEXT    NOT NULL DEFAULT 'CNY',
    direction       TEXT    NOT NULL CHECK (direction IN ('income', 'expense')),
    amount          INTEGER NOT NULL CHECK (amount > 0),
    category        TEXT
)
''';

/// 交易分类和 ICON 的映射
const String kCreateSqlIcons = '''
CREATE TABLE IF NOT EXISTS icons (
    category        TEXT PRIMARY KEY,
    icon            TEXT NOT NULL
)
''';

/// SQL 与数据字段的映射关系
const String kCreateSqlRules = '''
CREATE TABLE IF NOT EXISTS rules (
    name            TEXT PRIMARY KEY,
    date            TEXT    NOT NULL,
    type            TEXT    NOT NULL,
    counterparty    TEXT    NOT NULL,
    item            TEXT    NOT NULL,
    currency        TEXT,
    direction       TEXT    NOT NULL,
    amount          TEXT    NOT NULL,
    category        TEXT
)
''';

/// 建库时灌进 `icons` 的初始数据。之后一切以数据库为准，
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
      version: 1,
      onCreate: (db, _) => _createSchema(db),
      // 老库（v5）是旧表名，没有迁移价值：让 sqflite 把库删掉重建
      onDowngrade: onDatabaseDowngradeDelete,
      onOpen: _ensureSchema,
    ),
  );
}

Future<void> _createSchema(Database db) async {
  await db.execute(kCreateSqlEntries);
  await db.execute(kCreateSqlIcons);
  await db.execute(kCreateSqlRules);
  await _seedCategoryIcons(db);
}

/// 老库的表名叫 transactions / category_icon / settings。`entries` 不在就说明是旧库 ——
/// 其中一种已经被静默改成了 v1（降级时不报错、只改版本号），onCreate 不会再跑，这里补一次重建。
Future<void> _ensureSchema(Database db) async {
  final r = await db.rawQuery(
    "SELECT COUNT(*) AS c FROM sqlite_master "
    "WHERE type = 'table' AND name = 'entries'",
  );
  if (((r.first['c'] as int?) ?? 0) > 0) return;

  for (final t in ['transactions', 'category_icon', 'settings']) {
    await db.execute('DROP TABLE IF EXISTS $t');
  }
  await _createSchema(db);
}

/// 表为空时才灌初始数据。用户改过 / 删过就不动他。
Future<void> _seedCategoryIcons(Database db) async {
  final r = await db.rawQuery('SELECT COUNT(*) AS c FROM icons');
  if (((r.first['c'] as int?) ?? 0) > 0) return;
  final batch = db.batch();
  kDefaultCategoryIcons.forEach((category, iconName) {
    batch.insert('icons', {'category': category, 'icon': iconName});
  });
  await batch.commit(noResult: true);
}

/// uuidv7 生成器。库的默认随机源是 CryptoRNG，id 不可猜。
const Uuid _uuid = Uuid();

class TxnDao {
  final Database db;

  TxnDao(this.db);

  /// 新增，返回新行的 id。没带 id 的由这里补一个 uuidv7。
  Future<String> insert(Txn t) async {
    final map = t.toMap();
    final id = (map['id'] ??= _uuid.v7()) as String;
    await db.insert('entries', map);
    return id;
  }

  Future<int> update(Txn t) {
    final id = t.id;
    if (id == null) throw ArgumentError('要更新的流水没有 id');
    return db.update(
      'entries',
      t.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTxn(String id) =>
      db.delete('entries', where: 'id = ?', whereArgs: [id]);

  Future<Txn?> findById(String id) async {
    final rows = await db.query(
      'entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Txn.fromMap(rows.first);
  }

  /// 记过的分类 + icons 里配置过的分类。录入时给下拉建议用。
  Future<List<String>> knownCategories() async {
    final rows = await db.rawQuery('''
      SELECT DISTINCT category AS c FROM entries
        WHERE category IS NOT NULL AND category <> ''
      UNION
      SELECT category AS c FROM icons
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
      'entries',
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
  /// id 也在这里补齐 —— batch 拿不到逐行 rowid，uuidv7 没这个问题。
  Future<int> insertAll(Iterable<Txn> txns) async {
    final items = txns.toList();
    if (items.isEmpty) return 0;
    final batch = db.batch();
    for (final t in items) {
      final map = t.toMap();
      map['id'] ??= _uuid.v7();
      batch.insert('entries', map);
    }
    await batch.commit(noResult: true);
    return items.length;
  }

  Future<List<Txn>> listAll({int? limit}) async {
    final rows = await db.query(
      'entries',
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<int> count() async {
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM entries');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<Summary> summary() async {
    final r = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN "direction" = 'income'  THEN amount END), 0) AS income,
        COALESCE(SUM(CASE WHEN "direction" = 'expense' THEN amount END), 0) AS expense,
        COUNT(*) AS cnt
      FROM entries
    ''');
    final row = r.first;
    return Summary(
      incomeCents: (row['income'] as int?) ?? 0,
      expenseCents: (row['expense'] as int?) ?? 0,
      count: (row['cnt'] as int?) ?? 0,
    );
  }

  /// 整张分类映射表，带初始数据。页面加载一次即可。
  Future<Map<String, String>> categoryIcons() async {
    final rows = await db.query('icons');
    return {for (final r in rows) r['category'] as String: r['icon'] as String};
  }

  /// [iconName] 必须是 `AppIcons.choices` 里的名字。
  Future<void> setCategoryIcon(String category, String iconName) async {
    await db.insert('icons', {
      'category': category,
      'icon': iconName,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 恢复初始值；不在初始表里的分类直接删掉。
  Future<void> resetCategoryIcon(String category) async {
    final fallback = kDefaultCategoryIcons[category];
    if (fallback == null) {
      await db.delete('icons', where: 'category = ?', whereArgs: [category]);
    } else {
      await setCategoryIcon(category, fallback);
    }
  }

  // ────────────────────────────────────────── 解析方式

  /// 整张 rules 表，按插入顺序。
  Future<List<BillRule>> rules() async {
    final rows = await db.query('rules', orderBy: 'rowid');
    return rows.map(BillRule.fromRow).toList();
  }

  /// 名字是主键：有就改列名，没有就插。改名要走 [renameRule]，
  /// 否则改名字会变成「新增一条 + 留下旧的」。
  Future<void> saveRule(BillRule rule) async {
    final n = await db.update(
      'rules',
      rule.toRow()..remove('name'),
      where: 'name = ?',
      whereArgs: [rule.name],
    );
    if (n == 0) await db.insert('rules', rule.toRow());
  }

  Future<int> renameRule(String from, String to) =>
      db.update('rules', {'name': to}, where: 'name = ?', whereArgs: [from]);

  Future<int> deleteRule(String name) =>
      db.delete('rules', where: 'name = ?', whereArgs: [name]);

  // ────────────────────────────────────────── 日期区间

  /// [from] / [to] 是 'YYYY-MM-DD'，两端都含。
  /// date 列是 'YYYY-MM-DD HH:MM:SS'，字符串比较即可正确排序。
  Future<List<Txn>> listRange(String from, String to) async {
    final rows = await db.query(
      'entries',
      where: 'date >= ? AND date <= ?',
      whereArgs: ['$from 00:00:00', '$to 23:59:59'],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }
}
