import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';
import '../models.dart';
import '../stats.dart';

/// 支出视图 / 收入视图 切换：两个文字按钮，当前那个用主色加粗。
class DirectionToggle extends StatelessWidget {
  final bool expense;
  final ValueChanged<bool> onChanged;

  const DirectionToggle({
    super.key,
    required this.expense,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ViewButton(
          label: '支出',
          selected: expense,
          onPressed: () => onChanged(true),
        ),
        _ViewButton(
          label: '收入',
          selected: !expense,
          onPressed: () => onChanged(false),
        ),
      ],
    );
  }
}

class _ViewButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _ViewButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: selected ? cs.primary : cs.onSurfaceVariant,
        textStyle: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      child: Text(label),
    );
  }
}

/// 左上角的时间切换按钮：点开弹框选时间。
class RangeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const RangeButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 4),
          Icon(AppIcons.resolve('arrowDropDown'), size: 20),
        ],
      ),
    );
  }
}

/// 时间选择的年份范围
const int _pickerMinYear = 1970;

int get _pickerMaxYear => DateTime.now().year + 1;

const double _wheelItemExtent = 40;

/// 选年月：两个滚轮，左边年、右边月。取消返回 null。
Future<({int year, int month})?> showMonthWheelPicker(
  BuildContext context, {
  required int year,
  required int month,
}) {
  return showDialog<({int year, int month})>(
    context: context,
    builder: (_) => _WheelDialog(initialYear: year, initialMonth: month),
  );
}

/// 选年份：一列滚轮。取消返回 null。
Future<int?> showYearWheelPicker(
  BuildContext context, {
  required int year,
}) async {
  final r = await showDialog<({int year, int month})>(
    context: context,
    builder: (_) => _WheelDialog(initialYear: year),
  );
  return r?.year;
}

/// Material 里没有「滚轮选年月」这种弹框，用的是 Flutter 自带的 [CupertinoPicker]。
class _WheelDialog extends StatefulWidget {
  final int initialYear;

  /// 给了才有月份那一列
  final int? initialMonth;

  const _WheelDialog({required this.initialYear, this.initialMonth});

  @override
  State<_WheelDialog> createState() => _WheelDialogState();
}

class _WheelDialogState extends State<_WheelDialog> {
  late final List<int> _years = [
    for (var y = _pickerMinYear; y <= _pickerMaxYear; y++) y,
  ];

  late final int _yearIndex = (widget.initialYear - _pickerMinYear)
      .clamp(0, _years.length - 1)
      .toInt();

  late final FixedExtentScrollController _yearController =
      FixedExtentScrollController(initialItem: _yearIndex);

  FixedExtentScrollController? _monthController;

  @override
  void initState() {
    super.initState();
    final m = widget.initialMonth;
    if (m != null) {
      _monthController = FixedExtentScrollController(initialItem: m - 1);
    }
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController?.dispose();
    super.dispose();
  }

  /// 取滚轮停住的那一格，不是打开时那一格
  void _confirm() {
    final month = _monthController;
    Navigator.of(context).pop((
      year: _years[_yearController.selectedItem],
      month: month == null ? 1 : month.selectedItem + 1,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final month = _monthController;
    return AlertDialog(
      title: Text(month == null ? '选择年份' : '选择月份'),
      contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      content: SizedBox(
        height: 200,
        child: Row(
          children: [
            Expanded(
              child: _wheel(_yearController, [for (final y in _years) '$y 年']),
            ),
            if (month != null)
              Expanded(
                child: _wheel(month, [for (var m = 1; m <= 12; m++) '$m 月']),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _confirm, child: const Text('确定')),
      ],
    );
  }

  Widget _wheel(FixedExtentScrollController controller, List<String> labels) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.titleMedium
        ?.copyWith(color: cs.onSurface);

    // 选中底色不自己画：那层是画在文字上面的，换成不透明色会把中间那行盖住。
    return CupertinoPicker(
      itemExtent: _wheelItemExtent,
      scrollController: controller,
      onSelectedItemChanged: (_) {},
      children: [
        for (final label in labels) Center(child: Text(label, style: style)),
      ],
    );
  }
}

/// 区间合计
class TotalRow extends StatelessWidget {
  final bool expense;
  final int cents;
  final int count;

  const TotalRow({
    super.key,
    required this.expense,
    required this.cents,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            expense ? '支出' : '收入',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Text(
            formatCents(cents),
            style: tt.headlineSmall?.copyWith(
              color: expense ? cs.error : cs.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            '$count 笔',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 分类排行。带图标和占比条，跟列表页的图标映射用同一份配置。
class RankedList extends StatelessWidget {
  final List<CategorySum> items;
  final int totalCents;
  final bool expense;
  final Map<String, String> categoryIcons;

  const RankedList({
    super.key,
    required this.items,
    required this.totalCents,
    required this.expense,
    this.categoryIcons = const {},
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox(height: 40);

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = expense ? cs.error : cs.primary;
    final maxCents = items.first.cents;

    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.center,
                    style: tt.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 15,
                  backgroundColor: cs.surfaceContainerHighest,
                  child: Icon(
                    AppIcons.resolve(
                      iconNameForCategory(items[i].category, categoryIcons),
                    ),
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              items[i].category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatCents(items[i].cents),
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: maxCents <= 0
                                    ? 0
                                    : items[i].cents / maxCents,
                                minHeight: 4,
                                backgroundColor: cs.surfaceContainerHighest,
                                color: color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 56,
                            child: Text(
                              '${items[i].count} 笔 · '
                              '${totalCents <= 0 ? 0 : (items[i].cents / totalCents * 100).toStringAsFixed(0)}%',
                              textAlign: TextAlign.right,
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
