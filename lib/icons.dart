import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

abstract final class AppIcons {
  static const Map<String, IconData> uiIcons = {
    'emptyState': Symbols.receipt_long,
    'importBill': Symbols.file_download,
    'unknownCategory': Symbols.receipt_long,
    'tabList': Symbols.receipt_long,
    'tabMonth': Symbols.calendar_month,
    'tabYear': Symbols.bar_chart,
    'tabSettings': Symbols.settings,
    'addTxn': Symbols.edit_note,
    'addRule': Symbols.add,
    'search': Symbols.search,
    'deleteTxn': Symbols.delete_outline,
    'chevronRight': Symbols.chevron_right,
    'event': Symbols.event,
    'clear': Symbols.clear,
    'arrowDropDown': Symbols.arrow_drop_down,
    'restartAlt': Symbols.restart_alt,
    'palette': Symbols.palette,
    'aiConfig': Symbols.smart_toy,
    'importRecords': Symbols.history,
    'autoCategory': Symbols.rule,
    'recategorize': Symbols.autorenew,
  };

  static const Map<String, IconData> categoryIcons = {
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

  static IconData resolve(String? iconName) =>
      categoryIcons[iconName] ??
      uiIcons[iconName] ??
      uiIcons['unknownCategory']!;

  static List<String> get categoryIconNames => categoryIcons.keys.toList();
}
