import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';

import 'import/mapping_rules.dart';
import 'models.dart';

const String kCreateSqlEntries = '''
CREATE TABLE IF NOT EXISTS entries (
    id              TEXT    PRIMARY KEY,
    date            TEXT    NOT NULL,
    type            TEXT,
    counterparty    TEXT,
    item            TEXT,
    currency        TEXT    NOT NULL DEFAULT 'CNY',
    transaction     TEXT    NOT NULL CHECK (transaction IN ('income', 'expense')),
    amount          INTEGER NOT NULL CHECK (amount > 0),
    category        TEXT,
)
''';

/// 交易分类和 ICON 的映射
const String kCreateSqlIcons = '''
CREATE TABLE IF NOT EXISTS icons (
    category  TEXT PRIMARY KEY,
    icon TEXT NOT NULL
)
''';

/// SQL 与数据字段的映射关系
const String kCreateSqlRules = '''
CREATE TABLE IF NOT EXISTS rules (
    name   TEXT PRIMARY KEY,
    date            TEXT    NOT NULL,
    type            TEXT    NOT NULL,
    counterparty    TEXT    NOT NULL,
    item            TEXT    NOT NULL,
    currency        TEXT,
    transaction     TEXT    NOT NULL,
    amount          INTEGER NOT NULL,
    category        TEXT,
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
      version: 5,
      onCreate: (db, _) async {
        await db.execute(kCreateTableSql);
        await db.execute(kCreateCategoryIconSql);
        await db.execute(kCreateSettingsSql);
        await _seedCategoryIcons(db);
      },
      onUpgrade: (db, from, _) async {
        // v5 得排在最前面：它把老列名重建成新的，后面的播种 / 建表才写得进去
        if (from < 5) await _migrateToV5(db);
        if (from < 2) await db.execute(kCreateCategoryIconSql);
        if (from < 3) await _seedCategoryIcons(db);
        if (from < 4) await db.execute(kCreateSettingsSql);
      },
    ),
  );
}

/// v4 -> v5：主键从小自增整数换成 uuidv7 的 TEXT，金额列 `amount_cents` 改成 `cents`，
/// 分类图标列 `icon_name` 改成 `icon`。
///
/// SQLite 改不了主键类型，只能重建表。老行的新 id 拿它自己的 `date` 当时间戳交给
/// `uuid` 包生成 —— id 的字典序依然跟着日期走。
///
/// 注意 `date` 只到秒，**同一个 `date` 字符串的行会拿到同一个毫秒**（比如两笔发生在
/// 同一秒的交易）。v7 剩下那 74 位是纯随机、没有顺序含义，所以这几行之间在
/// `date DESC, id DESC` 里是随机先后 —— 唯一的例外，id 本身仍然是唯一的。
Future<void> _migrateToV5(Database db) async {
  final old = await db.query('transactions', orderBy: 'date, id');

  final batch = db.batch();
  batch.execute('DROP TABLE transactions');
  batch.execute(kCreateTableSql);
  for (final r in old) {
    final at = DateTime.tryParse('${r['date']}');
    batch.insert('transactions', {
      'id': _uuid.v7(config: V7Options(at?.millisecondsSinceEpoch, null)),
      'date': r['date'],
      'currency': r['currency'],
      'type': r['type'],
      'counterparty': r['counterparty'],
      'item': r['item'],
      'direction': r['direction'],
      'cents': r['amount_cents'] ?? r['cents'],
      'category': r['category'],
    });
  }
  await batch.commit(noResult: true);

  // category_icon 只要改列名。建表语句可能已经是新的了（老库版本低的话）。
  if ((await _columns(db, 'category_icon')).contains('icon_name')) {
    await db.execute('ALTER TABLE category_icon RENAME TO category_icon_old');
    await db.execute(kCreateCategoryIconSql);
    await db.execute(
      'INSERT INTO category_icon (category, icon) '
      'SELECT category, icon_name FROM category_icon_old',
    );
    await db.execute('DROP TABLE category_icon_old');
  }
}

Future<Set<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return {for (final r in rows) r['name'] as String};
}

/// 表为空时才灌初始数据。用户改过 / 删过就不动他。
Future<void> _seedCategoryIcons(Database db) async {
  final r = await db.rawQuery('SELECT COUNT(*) AS c FROM category_icon');
  if (((r.first['c'] as int?) ?? 0) > 0) return;
  final batch = db.batch();
  kDefaultCategoryIcons.forEach((category, iconName) {
    batch.insert('category_icon', {'category': category, 'icon': iconName});
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
    await db.insert('transactions', map);
    return id;
  }

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

  Future<int> deleteTxn(String id) =>
      db.delete('transactions', where: 'id = ?', whereArgs: [id]);

  Future<Txn?> findById(String id) async {
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
  /// id 也在这里补齐 —— batch 拿不到逐行 rowid，uuidv7 没这个问题。
  Future<int> insertAll(Iterable<Txn> txns) async {
    final items = txns.toList();
    if (items.isEmpty) return 0;
    final batch = db.batch();
    for (final t in items) {
      final map = t.toMap();
      map['id'] ??= _uuid.v7();
      batch.insert('transactions', map);
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
        COALESCE(SUM(CASE WHEN direction = 'income'  THEN cents END), 0) AS income,
        COALESCE(SUM(CASE WHEN direction = 'expense' THEN cents END), 0) AS expense,
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
      for (final r in rows) r['category'] as String: r['icon'] as String,
    };
  }

  /// [iconName] 必须是 `AppIcons.choices` 里的名字。
  Future<void> setCategoryIcon(String category, String iconName) async {
    await db.insert('category_icon', {
      'category': category,
      'icon': iconName,
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
