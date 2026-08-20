import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A form label with its input underneath.
///
/// Every field in the profile form is wrapped in this so labels always sit in
/// the same place with the same spacing.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.helperText,
  });

  final String label;
  final Widget child;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: text.titleSmall),
        if (helperText != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(helperText!, style: text.bodySmall),
        ],
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}
