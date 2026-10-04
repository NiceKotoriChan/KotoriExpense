import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/icons.dart';
import 'package:kotori_expense/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late TxnDao dao;

  setUp(() async {
    db = await openAppDb(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    dao = TxnDao(db);
  });

  tearDown(() => db.close());

  test('建库就把初始映射灌进表里', () async {
    expect(await dao.categoryIcons(), hasLength(kDefaultCategoryIcons.length));
  });

  test('初始映射用的图标名都在 choices 里', () async {
    for (final e in (await dao.categoryIcons()).entries) {
      expect(
        AppIcons.choices.containsKey(e.value),
        isTrue,
        reason: '「${e.key} -> ${e.value}」不在白名单里，运行时会静默变成兜底图标',
      );
    }
  });

  test('改分类图标', () async {
    await dao.setCategoryIcon('餐饮美食', 'local_cafe');
    expect((await dao.categoryIcons())['餐饮美食'], 'local_cafe');
    expect(await dao.categoryIcons(), hasLength(kDefaultCategoryIcons.length));
  });

  test('重置回到初始值', () async {
    await dao.setCategoryIcon('餐饮美食', 'local_cafe');
    await dao.resetCategoryIcon('餐饮美食');
    expect((await dao.categoryIcons())['餐饮美食'], kDefaultCategoryIcons['餐饮美食']);
  });

  test('重置不在初始表里的分类等于删掉它', () async {
    await dao.setCategoryIcon('自定义分类', 'bolt');
    expect((await dao.categoryIcons())['自定义分类'], 'bolt');
    await dao.resetCategoryIcon('自定义分类');
    expect((await dao.categoryIcons()).containsKey('自定义分类'), isFalse);
  });

  group('分类名 -> 图标名', () {
    test('精确命中', () {
      expect(iconNameForCategory('餐饮美食', kDefaultCategoryIcons), 'restaurant');
    });

    test('账单里带后缀的分类名走包含匹配', () {
      expect(iconNameForCategory('餐饮美食类', kDefaultCategoryIcons), 'restaurant');
      expect(
        iconNameForCategory('日用百货超市', kDefaultCategoryIcons),
        'shopping_basket',
      );
    });

    test('认不出返回 null', () {
      expect(iconNameForCategory('没见过', kDefaultCategoryIcons), isNull);
      expect(iconNameForCategory('', kDefaultCategoryIcons), isNull);
      expect(iconNameForCategory(null, kDefaultCategoryIcons), isNull);
    });
  });

  test('重开数据库不会覆盖用户改过的值', () async {
    final dir = Directory.systemTemp.createTempSync('kotori_db');
    final path = '${dir.path}/t.db';
    addTearDown(() => dir.deleteSync(recursive: true));

    final first = await openAppDb(path: path, factory: databaseFactoryFfi);
    await TxnDao(first).setCategoryIcon('餐饮美食', 'local_cafe');
    await first.close();

    final second = await openAppDb(path: path, factory: databaseFactoryFfi);
    expect((await TxnDao(second).categoryIcons())['餐饮美食'], 'local_cafe');
    await second.close();
  });
}
