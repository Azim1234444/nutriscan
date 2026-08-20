import 'text_limits.dart';

/// Validation rules for the nutrition fields a person can correct.
///
/// Both editors - the one used while reviewing a fresh analysis and the one
/// used on a meal already in history - call these, so the rules and the
/// wording cannot drift apart between the two screens.
class NutritionValidators {
  const NutritionValidators._();

  /// A meal has to be called something, and not something unbounded.
  ///
  /// Checked against the length the security rules already hold, so an
  /// over-long name is refused here, by a form that can say what is wrong -
  /// rather than by Firestore, which can only answer "permission denied" and
  /// leave the user guessing.
  ///
  /// The value is trimmed first because that is what the save writes, so a
  /// name padded with spaces is judged on what would actually be stored.
  static String? foodName(String? value) {
    final String name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter a food name';

    return TextLimits.lengthError(
      name,
      label: 'Food name',
      maxLength: TextLimits.foodName,
    );
  }

  /// A description is optional, so only its length is checked.
  ///
  /// Nothing in the security rules bounds this field, which is exactly why it
  /// is bounded here: without it, a description is the one stored string that
  /// could grow without limit.
  static String? description(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    return TextLimits.lengthError(
      text,
      label: 'Description',
      maxLength: TextLimits.description,
    );
  }

  /// Shared check for the numeric fields.
  ///
  /// [mustBePositive] is for portion size, which cannot be zero - a meal that
  /// weighs nothing is not a meal. Everything else may be zero but never
  /// negative.
  static String? amount(
    String? value, {
    required String field,
    bool mustBePositive = false,
  }) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter the $field';
    }
    final double? parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Enter $field as a number';
    if (parsed.isNaN || parsed.isInfinite) return 'Enter $field as a number';
    if (mustBePositive && parsed <= 0) {
      return 'Portion must be greater than 0';
    }
    if (parsed < 0) return '$field cannot be negative';
    return null;
  }
}
