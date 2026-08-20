import 'package:flutter/material.dart';

import '../models/food_entry.dart';
import '../models/macro.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import 'app_card.dart';
import 'edited_badge.dart';
import 'food_thumbnail.dart';
import 'macro_pill.dart';

/// Full history card: food name, when it was logged, calories and all macros.
class FoodHistoryCard extends StatelessWidget {
  const FoodHistoryCard({
    super.key,
    required this.entry,
    this.onTap,
    this.menu,
    this.isEdited = false,
    this.aiNote,
  });

  final FoodEntry entry;
  final VoidCallback? onTap;

  /// Per-meal actions, shown at the top right. Null leaves the card as it was
  /// before there was anything to do with a meal.
  final Widget? menu;

  /// Whether the values shown are the user's rather than the model's.
  final bool isEdited;

  /// What the model originally estimated, shown under the user's number so an
  /// edited meal never hides what the AI actually said.
  final String? aiNote;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FoodThumbnail(emoji: entry.emoji, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            entry.name,
                            style: text.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isEdited) ...<Widget>[
                          const SizedBox(width: AppSpacing.sm),
                          const EditedBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      Formatters.dayAndTime(entry.loggedAt),
                      style: text.bodySmall,
                    ),
                    Text(
                      '${entry.mealType.label} · ${entry.servingLabel}',
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
                    style: text.titleLarge?.copyWith(
                      color: AppColors.primaryDark,
                    ),
                  ),
                  Text('kcal', style: text.bodySmall),
                  if (aiNote != null)
                    Text(
                      aiNote!,
                      style: text.bodySmall,
                      textAlign: TextAlign.end,
                    ),
                ],
              ),
              ?menu,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final Macro macro in Macro.values)
                MacroPill(macro: macro, grams: macro.valueIn(entry.nutrition)),
            ],
          ),
        ],
      ),
    );
  }
}
