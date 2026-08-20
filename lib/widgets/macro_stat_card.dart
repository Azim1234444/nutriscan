import 'package:flutter/material.dart';

import '../models/macro.dart';
import '../models/nutrition_summary.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/macro_visuals.dart';
import '../utils/formatters.dart';

/// Dashboard tile showing one macro: eaten grams, target and a progress bar.
class MacroStatCard extends StatelessWidget {
  const MacroStatCard({
    super.key,
    required this.macro,
    required this.consumedG,
    required this.targetG,
  });

  final Macro macro;
  final double consumedG;
  final double targetG;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color color = MacroVisuals.color(macro);
    final double progress = NutritionSummary.progress(consumedG, targetG);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: MacroVisuals.softColor(macro),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(MacroVisuals.icon(macro), size: 16, color: color),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  macro.label,
                  style: text.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.grams(consumedG),
              style: text.titleLarge?.copyWith(fontSize: 20),
            ),
          ),
          Text('of ${Formatters.grams(targetG)}', style: text.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: MacroVisuals.softColor(macro),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
