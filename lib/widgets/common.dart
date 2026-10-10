import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';
import '../import/ai_parser.dart';
import '../models.dart';

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

Future<String?> showTextDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String confirmText = '保存',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _TextDialog(title: title, initial: initial, hint: hint, confirmText: confirmText),
  );
}

class _TextDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String? hint;
  final String confirmText;

  const _TextDialog({
    required this.title,
    required this.initial,
    this.hint,
    required this.confirmText,
  });

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _ctrl.text.length,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }
}

const int _pickerMinYear = 1970;

int get _pickerMaxYear => DateTime.now().year + 1;

const double _wheelItemExtent = 40;

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

class _WheelDialog extends StatefulWidget {
  final int initialYear;
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

class AiTraceView extends StatelessWidget {
  final AiTrace trace;
  final String? outcome;

  const AiTraceView({super.key, required this.trace, this.outcome});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = trace;

    final request = <Widget>[
      Text(t.endpoint),
      if (t.model.isNotEmpty) Text('model: ${t.model}'),
      if (t.system != null) _oneLine('提示词：${t.system}'),
      _oneLine('发送 ${t.userChars} 字：${t.user}'),
    ];

    final response = <Widget>[
      if (t.status == null)
        Text(t.error ?? '没有响应', style: TextStyle(color: cs.error))
      else ...[
        Text(
          'HTTP ${t.status} · ${t.elapsedMs} ms',
          style: TextStyle(color: t.ok ? cs.primary : cs.error),
        ),
        if (t.error != null) Text(t.error!, style: TextStyle(color: cs.error)),
        if (!t.ok && t.body.isNotEmpty) _dump(t.body, cs.onSurfaceVariant),
        if (t.reply != null) _dump('回答 ${t.reply!.length} 字：${t.reply}'),
      ],
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(context, '请求', request),
          const SizedBox(height: 12),
          _row(context, '响应', response),
          if (outcome != null) ...[
            const SizedBox(height: 12),
            _row(context, '解析', [
              Text(outcome!, style: TextStyle(color: cs.primary)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _oneLine(String text) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

  Widget _dump(String text, [Color? color]) => Text(
    _flatten(text),
    maxLines: 6,
    overflow: TextOverflow.ellipsis,
    style: color == null ? null : TextStyle(color: color),
  );

  String _flatten(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > kTraceBodyChars ? '${t.substring(0, kTraceBodyChars)}…' : t;
  }

  Widget _row(BuildContext context, String label, List<Widget> lines) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in lines)
                Padding(padding: const EdgeInsets.only(bottom: 2), child: l),
            ],
          ),
        ),
      ],
    );
  }
}

class RankedList extends StatelessWidget {
  final List<Txn> items;
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

  static String _title(Txn t) {
    for (final v in [t.counterparty, t.item, t.type, t.category]) {
      if (v != null && v.trim().isNotEmpty) return v;
    }
    return '未分类';
  }

  static String _caption(Txn t, int totalCents) {
    final date = t.date.length >= 10 ? t.date.substring(5, 10) : t.date;
    final percent = totalCents <= 0
        ? 0
        : (t.amountCents / totalCents * 100).round();
    return '$date · $percent%';
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox(height: 40);

    final maxCents = items.first.amountCents;

    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          _RankedRow(
            rank: i + 1,
            txn: items[i],
            maxCents: maxCents,
            totalCents: totalCents,
            expense: expense,
            categoryIcons: categoryIcons,
          ),
      ],
    );
  }
}

class _RankedRow extends StatelessWidget {
  final int rank;
  final Txn txn;
  final int maxCents;
  final int totalCents;
  final bool expense;
  final Map<String, String> categoryIcons;

  const _RankedRow({
    required this.rank,
    required this.txn,
    required this.maxCents,
    required this.totalCents,
    required this.expense,
    required this.categoryIcons,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = expense ? cs.error : cs.primary;

    final title = RankedList._title(txn);
    final category = txn.category;
    final label = category == null || category == title
        ? title
        : '$title · $category';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
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
              AppIcons.resolve(iconNameForCategory(category, categoryIcons)),
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
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${expense ? '-' : '+'}${formatCents(txn.amountCents)}',
                      style: tt.bodyMedium?.copyWith(
                        color: color,
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
                          value: maxCents <= 0 ? 0 : txn.amountCents / maxCents,
                          minHeight: 4,
                          backgroundColor: cs.surfaceContainerHighest,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 76,
                      child: Text(
                        RankedList._caption(txn, totalCents),
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
    );
  }
}
