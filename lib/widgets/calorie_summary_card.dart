import 'package:flutter/material.dart';

import '../models/nutrition_summary.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import 'app_card.dart';

/// "Today's progress" hero card: a calorie ring plus eaten / remaining totals.
class CalorieSummaryCard extends StatelessWidget {
  const CalorieSummaryCard({
    super.key,
    required this.consumed,
    required this.target,
  });

  final NutritionSummary consumed;
  final NutritionSummary target;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double remaining = (target.calories - consumed.calories).clamp(
      0,
      double.infinity,
    );
    final double progress = NutritionSummary.progress(
      consumed.calories,
      target.calories,
    );

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text("Today's progress", style: text.titleLarge)),
              Text(
                '${(progress * 100).round()}%',
                style: text.titleMedium?.copyWith(color: AppColors.primaryDark),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              _CalorieRing(progress: progress, remaining: remaining),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _CalorieStat(
                      label: 'Eaten',
                      value: Formatters.calories(consumed.calories),
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _CalorieStat(
                      label: 'Daily goal',
                      value: Formatters.calories(target.calories),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Circular calorie indicator with the remaining calories in the middle.
class _CalorieRing extends StatelessWidget {
  const _CalorieRing({required this.progress, required this.remaining});

  final double progress;
  final double remaining;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SizedBox(
      height: 116,
      width: 116,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 10,
              strokeCap: StrokeCap.round,
              backgroundColor: AppColors.primarySoft,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Formatters.calories(remaining),
                style: text.headlineSmall?.copyWith(
                  color: AppColors.primaryDark,
                ),
              ),
              Text('kcal left', style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// One label + number pair next to the ring.
class _CalorieStat extends StatelessWidget {
  const _CalorieStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Container(
          height: 10,
          width: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: text.bodyMedium)),
        Text('$value kcal', style: text.titleMedium),
      ],
    );
  }
}
