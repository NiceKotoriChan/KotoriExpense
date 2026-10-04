import 'package:flutter/material.dart';

import '../db.dart';
import '../icons.dart';
import '../models.dart';
import '../stats.dart';

/// 按天分组的紧凑流水列表。列表页和搜索页共用。
class TxnDayList extends StatelessWidget {
  final List<Txn> txns;
  final Map<String, String> categoryIcons;
  final ValueChanged<Txn> onTap;
  final EdgeInsetsGeometry padding;

  const TxnDayList({
    super.key,
    required this.txns,
    required this.onTap,
    this.categoryIcons = const {},
    this.padding = const EdgeInsets.only(bottom: 96),
  });

  @override
  Widget build(BuildContext context) {
    final rows = <_Row>[];
    for (final g in groupByDay(txns)) {
      rows.add(_DayRow(g));
      for (final t in g.txns) {
        rows.add(_TxnRow(t));
      }
    }

    return ListView.builder(
      padding: padding,
      itemCount: rows.length,
      itemBuilder: (_, i) => switch (rows[i]) {
        _DayRow(:final group) => _DayHeader(group: group),
        _TxnRow(:final txn) => TxnCompactTile(
          txn: txn,
          categoryIcons: categoryIcons,
          onTap: () => onTap(txn),
        ),
      },
    );
  }
}

sealed class _Row {
  const _Row();
}

class _DayRow extends _Row {
  final DayGroup group;
  const _DayRow(this.group);
}

class _TxnRow extends _Row {
  final Txn txn;
  const _TxnRow(this.txn);
}

/// 某一天的分隔条：日期 + 当天进出合计
class _DayHeader extends StatelessWidget {
  final DayGroup group;

  const _DayHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
        children: [
          Text(
            dayLabel(group.date),
            style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          if (group.expenseCents > 0)
            Text(
              '支出 ${formatCents(group.expenseCents)}',
              style: tt.labelSmall?.copyWith(color: cs.error),
            ),
          if (group.expenseCents > 0 && group.incomeCents > 0)
            const SizedBox(width: 10),
          if (group.incomeCents > 0)
            Text(
              '收入 ${formatCents(group.incomeCents)}',
              style: tt.labelSmall?.copyWith(color: cs.primary),
            ),
        ],
      ),
    );
  }
}

/// 一条流水。dense + compact，比默认 ListTile 矮一截。
class TxnCompactTile extends StatelessWidget {
  final Txn txn;
  final Map<String, String> categoryIcons;
  final VoidCallback? onTap;

  const TxnCompactTile({
    super.key,
    required this.txn,
    this.categoryIcons = const {},
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final title = txn.counterparty ?? txn.item ?? txn.category ?? '未分类';
    final sub = <String>[
      if (txn.category != null && txn.category != title) txn.category!,
      if (txn.item != null && txn.item != title) txn.item!,
      if (txn.type != null && txn.type!.isNotEmpty) txn.type!,
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: 24,
      horizontalTitleGap: 12,
      leading: Icon(
        AppIcons.resolve(iconNameForCategory(txn.category, categoryIcons)),
        size: 20,
        color: cs.onSurfaceVariant,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium,
      ),
      subtitle: sub.isEmpty
          ? null
          : Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
      trailing: Text(
        '${txn.isExpense ? '-' : '+'}${formatCents(txn.amountCents)}',
        style: tt.bodyMedium?.copyWith(
          color: txn.isExpense ? cs.error : cs.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
