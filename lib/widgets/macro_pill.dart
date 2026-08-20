import 'package:flutter/material.dart';

import '../models/macro.dart';
import '../theme/app_spacing.dart';
import '../theme/macro_visuals.dart';
import '../utils/formatters.dart';

/// Compact "P 42 g" style chip used on meal and history cards.
class MacroPill extends StatelessWidget {
  const MacroPill({super.key, required this.macro, required this.grams});

  final Macro macro;
  final double grams;

  @override
  Widget build(BuildContext context) {
    final Color color = MacroVisuals.color(macro);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: MacroVisuals.softColor(macro),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '${macro.label} ${Formatters.grams(grams)}',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
