import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'labeled_field.dart';

/// Labelled text input used by the profile form.
///
/// Set [isNumeric] for measurements: it switches to the number keyboard and
/// blocks characters that are not digits or a decimal point.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.suffixText,
    this.isNumeric = false,
    this.textInputAction = TextInputAction.next,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final String? suffixText;
  final bool isNumeric;
  final TextInputAction textInputAction;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: label,
      child: TextFormField(
        controller: controller,
        validator: validator,
        textInputAction: textInputAction,
        keyboardType: isNumeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: isNumeric
            ? <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ]
            : null,
        textCapitalization: isNumeric
            ? TextCapitalization.none
            : TextCapitalization.words,
        decoration: InputDecoration(hintText: hintText, suffixText: suffixText),
      ),
    );
  }
}
