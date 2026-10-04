import 'package:flutter_test/flutter_test.dart';
import 'package:kotori_expense/icons.dart';

/// 这个文件只管翻译层：名字 -> IconData。
/// 分类映射是数据库的事，验在 category_icons_test.dart。
void main() {
  test('认识的名字翻译成对应图标', () {
    expect(AppIcons.resolve('restaurant'), AppIcons.choices['restaurant']);
    expect(AppIcons.resolve('emptyState'), AppIcons.choices['emptyState']);
  });

  test('认不出 / 空值兜底，不抛异常', () {
    final fallback = AppIcons.choices['unknownCategory'];
    expect(AppIcons.resolve('没这个图标'), fallback);
    expect(AppIcons.resolve(''), fallback);
    expect(AppIcons.resolve(null), fallback);
  });

  test('分类图标的名字都是小写加下划线', () {
    for (final key in AppIcons.categoryIconNames) {
      expect(
        RegExp(r'^[a-z0-9_]+$').hasMatch(key),
        isTrue,
        reason: '「$key」不合规范',
      );
    }
  });

  test('分类图标里没有两个名字指向同一个字形', () {
    final seen = <int, String>{};
    for (final name in AppIcons.categoryIconNames) {
      final cp = AppIcons.choices[name]!.codePoint;
      final prev = seen[cp];
      expect(prev, isNull, reason: '「$name」与「$prev」是同一个字形');
      seen[cp] = name;
    }
  });

  test('界面图标不出现在分类图标清单里', () {
    for (final name in AppIcons.uiOnly) {
      expect(
        AppIcons.choices.containsKey(name),
        isTrue,
        reason: '「$name」没在 choices 里',
      );
      expect(AppIcons.categoryIconNames.contains(name), isFalse);
    }
  });
}
