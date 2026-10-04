import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 页面里的读库是真异步（sqflite_common_ffi 跑在另一个 isolate），
/// widget test 的假时钟等不到它；而加载中那一转不停的 CircularProgressIndicator
/// 又会让 pumpAndSettle 永远等不到静止。所以只能这么来：
/// **pump 几帧 与 runAsync 交替**。
///
/// 必须交替 —— 点导航要先把动画 pump 起来，页面 build 出来才开始读库，
/// 读库又要 runAsync 才能完成。一口气 pump 完再让出去就晚了一拍。
Future<void> settle(WidgetTester tester) async {
  for (var round = 0; round < 4; round++) {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
  }
  await tester.pump();
}

/// 默认给个高视口：ListView 是懒构建的，屏幕外的区块根本不会建出来，
/// 断言会莫名其妙落空。窄屏布局由 charts_test.dart 单独覆盖。
void setView(WidgetTester tester, {double width = 400, double height = 1600}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 在假时钟里跑一次真数据库调用并拿到结果。
/// 直接 `await dao.xxx()` 会永远挂住 —— 见上面 [settle] 的说明。
Future<T> dbCall<T>(WidgetTester tester, Future<T> Function() run) async {
  late T result;
  await tester.runAsync(() async {
    result = await run();
  });
  return result;
}

/// 开一个只属于当前测试的库。
///
/// **不要用 `inMemoryDatabasePath` 做 widget test** —— 那个路径在同一个进程里是共享的：
/// sqflite_common_ffi 按路径缓存已打开的库，测试里又不会 close，
/// 于是第二个测试 open 拿到的是同一个库，数据全串在一起。
/// 用 `test()` 的那些用例没事，是因为它们在 setUp/tearDown 里真的 close 了。
Future<TxnDao> openTempDb(WidgetTester tester) async {
  final dir = Directory.systemTemp.createTempSync('kotori_test');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // 库还开着时删不掉也无所谓，临时目录而已
    }
  });

  return dbCall(tester, () async {
    final db = await openAppDb(
      path: '${dir.path}/app.db',
      factory: databaseFactoryFfi,
    );
    return TxnDao(db);
  });
}
