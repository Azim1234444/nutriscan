import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'labeled_field.dart';

/// Single-choice chip row, e.g. Male / Female / Other.
///
/// Generic over [T] so it works with any enum in the app.
class OptionChips<T> extends StatelessWidget {
  const OptionChips({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
  });

  final String label;
  final List<T> options;
  final T selected;
  final String Function(T option) labelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: label,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          for (final T option in options)
            ChoiceChip(
              label: Text(labelBuilder(option)),
              selected: option == selected,
              onSelected: (bool isSelected) {
                if (isSelected) onSelected(option);
              },
            ),
        ],
      ),
    );
  }
}
