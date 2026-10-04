import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 这是项目的 icon 集合
abstract final class AppIcons {
  static const Map<String, IconData> choices = {
    // 界面图标（见 uiOnly，不进分类图标选择器）
    'emptyState': Symbols.receipt_long,
    'importBill': Symbols.file_download,
    'pickFile': Symbols.folder_open,
    'unknownCategory': Symbols.receipt_long,
    'tabList': Symbols.receipt_long,
    'tabMonth': Symbols.calendar_month,
    'tabYear': Symbols.bar_chart,
    'tabSettings': Symbols.settings,
    'addTxn': Symbols.edit_note,
    'addRule': Symbols.add,
    'search': Symbols.search,
    'deleteTxn': Symbols.delete_outline,
    'chevronLeft': Symbols.chevron_left,
    'chevronRight': Symbols.chevron_right,
    'event': Symbols.event,
    'schedule': Symbols.schedule,
    'clear': Symbols.clear,
    'arrowDropDown': Symbols.arrow_drop_down,
    'restartAlt': Symbols.restart_alt,
    'tableChart': Symbols.table_chart,
    'palette': Symbols.palette,
    // 分类图标
    'restaurant': Symbols.restaurant,
    'local_cafe': Symbols.local_cafe,
    'fastfood': Symbols.fastfood,
    'shopping_basket': Symbols.shopping_basket,
    'shopping_bag': Symbols.shopping_bag,
    'shopping_cart': Symbols.shopping_cart,
    'directions_car': Symbols.directions_car,
    'directions_bus': Symbols.directions_bus,
    'local_taxi': Symbols.local_taxi,
    'train': Symbols.train,
    'directions_bike': Symbols.directions_bike,
    'devices': Symbols.devices,
    'smartphone': Symbols.smartphone,
    'computer': Symbols.computer,
    'checkroom': Symbols.checkroom,
    'content_cut': Symbols.content_cut,
    'spa': Symbols.spa,
    'home_repair_service': Symbols.home_repair_service,
    'cleaning_services': Symbols.cleaning_services,
    'local_laundry_service': Symbols.local_laundry_service,
    'medical_services': Symbols.medical_services,
    'medication': Symbols.medication,
    'fitness_center': Symbols.fitness_center,
    'health_and_safety': Symbols.health_and_safety,
    'sports_esports': Symbols.sports_esports,
    'local_activity': Symbols.local_activity,
    'school': Symbols.school,
    'menu_book': Symbols.menu_book,
    'home': Symbols.home,
    'apartment': Symbols.apartment,
    'bolt': Symbols.bolt,
    'savings': Symbols.savings,
    'trending_up': Symbols.trending_up,
    'account_balance': Symbols.account_balance,
    'credit_card': Symbols.credit_card,
    'payments': Symbols.payments,
    'receipt_long': Symbols.receipt_long,
    'swap_horiz': Symbols.swap_horiz,
    'currency_exchange': Symbols.currency_exchange,
    'redeem': Symbols.redeem,
    'group': Symbols.group,
    'work': Symbols.work,
    'business_center': Symbols.business_center,
    'pets': Symbols.pets,
    'child_care': Symbols.child_care,
    'flight': Symbols.flight,
    'local_florist': Symbols.local_florist,
    'more_horiz': Symbols.more_horiz,
  };

  /// 名字认不出来就兜底，不抛异常 —— 图标错了不该让页面崩。
  static IconData resolve(String? iconName) =>
      choices[iconName] ?? choices['unknownCategory']!;

  /// 只给界面用，做分类图标选择器时要按这张表过滤掉
  static const Set<String> uiOnly = {
    'emptyState',
    'importBill',
    'pickFile',
    'unknownCategory',
    'tabList',
    'tabMonth',
    'tabYear',
    'tabSettings',
    'addTxn',
    'addRule',
    'search',
    'deleteTxn',
    'chevronLeft',
    'chevronRight',
    'event',
    'schedule',
    'clear',
    'arrowDropDown',
    'restartAlt',
    'tableChart',
    'palette',
  };

  /// 分类图标的名字，按定义顺序
  static List<String> get categoryIconNames =>
      choices.keys.where((k) => !uiOnly.contains(k)).toList();
}
