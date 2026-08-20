import 'package:flutter/material.dart';

import '../models/food_entry.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import 'app_card.dart';
import 'food_thumbnail.dart';

/// Compact meal row used in the "Recent meals" list on the dashboard.
class MealTile extends StatelessWidget {
  const MealTile({super.key, required this.entry, this.onTap});

  final FoodEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          FoodThumbnail(emoji: entry.emoji),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.name,
                  style: text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${entry.mealType.label} · ${Formatters.time(entry.loggedAt)}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                Formatters.calories(entry.calories),
                style: text.titleMedium?.copyWith(color: AppColors.primaryDark),
              ),
              Text('kcal', style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
