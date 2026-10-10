import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';

const List<Color> kChartPalette = [
  Color(0xFF3F7D6E),
  Color(0xFFE8A33D),
  Color(0xFF5B8DEF),
  Color(0xFFD9534F),
  Color(0xFF8E7CC3),
  Color(0xFF4FA3A5),
  Color(0xFFE2725B),
  Color(0xFF7BA05B),
  Color(0xFFC06C9B),
  Color(0xFF9C8E7A),
];

Color chartColorAt(int i) => kChartPalette[i % kChartPalette.length];

class ChartSection extends StatelessWidget {
  final String title;
  final Widget child;

  const ChartSection({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: tt.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class ChartEmpty extends StatelessWidget {
  final String text;

  const ChartEmpty({super.key, this.text = '这个区间没有数据'});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}

class ChartSlice {
  final String label;
  final int value;

  const ChartSlice(this.label, this.value);
}

class PieChart extends StatelessWidget {
  final List<ChartSlice> slices;
  final double size;

  const PieChart({super.key, required this.slices, this.size = 132});

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (a, s) => a + s.value);
    if (total <= 0) return const ChartEmpty();

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(
              values: [for (final s in slices) s.value],
              strokeWidth: size * 0.22,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < slices.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: chartColorAt(i),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          slices[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(slices[i].value / total * 100).toStringAsFixed(1)}%',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
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

class _DonutPainter extends CustomPainter {
  final List<int> values;
  final double strokeWidth;

  const _DonutPainter({required this.values, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return;

    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = values[i] / total * 2 * math.pi;
      paint.color = chartColorAt(i);
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.strokeWidth != strokeWidth || !identical(old.values, values);
}

class BarChart extends StatelessWidget {
  final List<int> values;
  final List<String> labels;
  final Color color;
  final double height;

  const BarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(0, math.max);
    if (maxValue <= 0) return const ChartEmpty();

    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final barMax = height - 26;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (values[i] > 0)
                          Container(
                            height: math.max(2, values[i] / maxValue * barMax),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          labels[i],
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '最高 ${formatCents(maxValue)}',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class CalendarHeatmap extends StatelessWidget {
  final int year;
  final int month;

  final List<int> dailyTotals;
  final Color color;

  const CalendarHeatmap({
    super.key,
    required this.year,
    required this.month,
    required this.dailyTotals,
    required this.color,
  });

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final days = dailyTotals.length - 1;
    if (days <= 0) return const ChartEmpty();

    final maxValue = dailyTotals.fold<int>(0, math.max);
    final leading = DateTime(year, month, 1).weekday - 1;

    final cells = <Widget?>[
      ...List<Widget?>.filled(leading, null),
      for (var d = 1; d <= days; d++) _dayCell(context, d, maxValue),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final w in _weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < cells.length ~/ 7; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(1.5),
                      child: cells[r * 7 + c] ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
            ],
          ),
        if (maxValue > 0) ...[
          const SizedBox(height: 8),
          Text(
            '单日最高 ${formatCents(maxValue)}',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _dayCell(BuildContext context, int day, int maxValue) {
    final cs = Theme.of(context).colorScheme;
    final value = dailyTotals[day];
    final intensity = maxValue <= 0 ? 0.0 : 0.10 + 0.75 * (value / maxValue);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: value <= 0
            ? cs.surfaceContainerHighest
            : color.withValues(alpha: intensity),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: intensity > 0.55 ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
