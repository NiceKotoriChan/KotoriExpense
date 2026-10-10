import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import 'auto_category.dart';
import 'models.dart';

const String kCreateSqlEntries = '''
CREATE TABLE IF NOT EXISTS entries (
    id              TEXT PRIMARY KEY,
    date            TEXT NOT NULL,
    type            TEXT,
    counterparty    TEXT,
    item            TEXT,
    currency        TEXT NOT NULL DEFAULT 'CNY',
    direction       TEXT NOT NULL CHECK (direction IN ('income', 'expense')),
    amount          INTEGER NOT NULL CHECK (amount > 0),
    category        TEXT,
    record          INTEGER NOT NULL REFERENCES records(id) ON DELETE CASCADE
)
''';

const String kCreateSqlIcons = '''
CREATE TABLE IF NOT EXISTS icons (
    category        TEXT PRIMARY KEY,
    icon            TEXT NOT NULL
)
''';

const String kCreateSqlRecords = '''
CREATE TABLE IF NOT EXISTS records (
    id              INTEGER PRIMARY KEY,
    name            TEXT UNIQUE
)
''';

const String kCreateSqlSettings = '''
CREATE TABLE IF NOT EXISTS settings (
    key             TEXT PRIMARY KEY,
    value           TEXT NOT NULL
)
''';

const String kCreateSqlTriggerDropEmptyRecord = '''
CREATE TRIGGER IF NOT EXISTS trg_drop_empty_record
AFTER DELETE ON entries
WHEN (SELECT COUNT(*) FROM entries WHERE record = OLD.record) = 0
BEGIN
    DELETE FROM records WHERE id = OLD.record;
END
''';

String? iconNameForCategory(String? category, Map<String, String> mapping) {
  if (category == null || category.isEmpty) return null;
  final exact = mapping[category];
  if (exact != null) return exact;
  for (final e in mapping.entries) {
    if (category.contains(e.key)) return e.value;
  }
  return null;
}

class RecordSummary {
  final int id;
  final String name;
  final int count;
  final int incomeCents;
  final int expenseCents;

  const RecordSummary({
    required this.id,
    required this.name,
    required this.count,
    required this.incomeCents,
    required this.expenseCents,
  });

  int get balanceCents => incomeCents - expenseCents;
}

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
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => _createSchema(db),
      onDowngrade: onDatabaseDowngradeDelete,
    ),
  );
}

Future<void> _createSchema(Database db) async {
  await db.execute(kCreateSqlRecords);
  await db.execute(kCreateSqlEntries);
  await db.execute(kCreateSqlIcons);
  await db.execute(kCreateSqlSettings);
  await db.execute(kCreateSqlTriggerDropEmptyRecord);
}

const Uuid _uuid = Uuid();

const String kManualRecordName = '手动';

class TxnDao {
  final Database db;

  TxnDao(this.db);

  Future<String> insert(Txn t, {required String source}) async {
    final rid = await recordIdFor(source);
    final map = t.toMap()..['record'] = rid;
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

  Future<int> updateAll(Iterable<Txn> txns) async {
    final batch = db.batch();
    var n = 0;
    for (final t in txns) {
      final id = t.id;
      if (id == null) continue;
      batch.update(
        'entries',
        t.toMap()..remove('id'),
        where: 'id = ?',
        whereArgs: [id],
      );
      n++;
    }
    await batch.commit(noResult: true);
    return n;
  }

  Future<List<Txn>> uncategorized() async {
    final rows = await db.query(
      'entries',
      where: "category IS NULL OR TRIM(category) = ''",
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<int> deleteTxn(String id) =>
      db.delete('entries', where: 'id = ?', whereArgs: [id]);

  Future<List<String>> knownCategories() async {
    final rows = await db.rawQuery('''
      SELECT DISTINCT category AS c FROM entries
        WHERE category IS NOT NULL AND category <> ''
      UNION
      SELECT category AS c FROM icons
    ''');
    return [for (final r in rows) r['c'] as String]..sort();
  }

  Future<List<Txn>> search(String keyword, {int limit = 300}) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];
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

  Future<int> insertAll(Iterable<Txn> txns, {required String source}) async {
    final items = txns.toList();
    if (items.isEmpty) return 0;
    final rid = await recordIdFor(source);
    final batch = db.batch();
    for (final t in items) {
      final map = t.toMap()..['record'] = rid;
      map['id'] ??= _uuid.v7();
      batch.insert('entries', map);
    }
    await batch.commit(noResult: true);
    return items.length;
  }

  Future<int> recordIdFor(String name) async {
    final rows = await db.query(
      'records',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;
    return db.insert('records', {'name': name});
  }

  Future<List<Txn>> listAll({int? limit}) async {
    final rows = await db.query(
      'entries',
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<String?> latestDate() async {
    final r = await db.rawQuery('SELECT MAX(date) AS d FROM entries');
    return r.first['d'] as String?;
  }

  Future<Map<String, String>> categoryIcons() async {
    final rows = await db.query('icons');
    return {for (final r in rows) r['category'] as String: r['icon'] as String};
  }

  Future<void> setCategoryIcon(String category, String iconName) async {
    await db.insert('icons', {
      'category': category,
      'icon': iconName,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearCategoryIcon(String category) =>
      db.delete('icons', where: 'category = ?', whereArgs: [category]);

  Future<List<Txn>> listRange(String from, String to) async {
    final rows = await db.query(
      'entries',
      where: 'date >= ? AND date <= ?',
      whereArgs: [from, to],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<List<RecordSummary>> recordSummaries() async {
    final rows = await db.rawQuery('''
      SELECT r.id        AS id,
             r.name      AS name,
             COUNT(e.id) AS cnt,
             COALESCE(SUM(CASE WHEN e."direction" = 'income'  THEN e.amount END), 0) AS income,
             COALESCE(SUM(CASE WHEN e."direction" = 'expense' THEN e.amount END), 0) AS expense,
             MAX(e.date) AS last
        FROM records r
        LEFT JOIN entries e ON e.record = r.id
       GROUP BY r.id, r.name
       ORDER BY last DESC, r.id DESC
    ''');
    return [
      for (final r in rows)
        RecordSummary(
          id: r['id'] as int,
          name: (r['name'] as String?) ?? '',
          count: (r['cnt'] as int?) ?? 0,
          incomeCents: (r['income'] as int?) ?? 0,
          expenseCents: (r['expense'] as int?) ?? 0,
        ),
    ];
  }

  Future<int> renameRecord(int id, String name) =>
      db.update('records', {'name': name}, where: 'id = ?', whereArgs: [id]);

  Future<int> deleteRecord(int id) =>
      db.delete('records', where: 'id = ?', whereArgs: [id]);

  Future<Map<String, String>> settings() async {
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<List<CategoryRule>> categoryRules() async {
    final s = await settings();
    return decodeRules(s[kCategoryRulesKey]);
  }

  Future<void> saveCategoryRules(List<CategoryRule> rules) =>
      saveSettings({kCategoryRulesKey: encodeRules(rules)});

  Future<void> saveSettings(Map<String, String> values) async {
    final batch = db.batch();
    values.forEach((k, v) {
      batch.insert(
        'settings',
        {'key': k, 'value': v},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }
}
