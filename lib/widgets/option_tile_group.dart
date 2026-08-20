import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'labeled_field.dart';

/// Vertical list of selectable cards, each with a title and a description.
///
/// Used for activity level and goal, where the options need more explanation
/// than a small chip can carry.
class OptionTileGroup<T> extends StatelessWidget {
  const OptionTileGroup({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.titleBuilder,
    required this.descriptionBuilder,
    required this.onSelected,
  });

  final String label;
  final List<T> options;
  final T selected;
  final String Function(T option) titleBuilder;
  final String Function(T option) descriptionBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: label,
      child: Column(
        children: <Widget>[
          for (final T option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _OptionTile(
                title: titleBuilder(option),
                description: descriptionBuilder(option),
                isSelected: option == selected,
                onTap: () => onSelected(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Material(
      color: isSelected ? AppColors.primarySoft : AppColors.surface,
      borderRadius: AppRadius.fieldRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.fieldRadius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppRadius.fieldRadius,
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.outline,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: text.titleSmall),
                      const SizedBox(height: 2),
                      Text(description, style: text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: isSelected ? AppColors.primary : AppColors.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
