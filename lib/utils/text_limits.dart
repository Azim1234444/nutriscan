import 'dart:convert';

/// How long the app's stored text fields are allowed to be.
///
/// [profileName] and [foodName] are not chosen here. They are the caps the
/// Firestore security rules already hold, written down once so the forms, the
/// model parser and the rules cannot drift apart - the same reason the age and
/// weight bounds are mirrored in the profile model. [description] has no rule
/// behind it and is the app's own bound; see its note.
///
/// Lengths are counted in UTF-8 bytes. The rules measure with `size()`, and a
/// UTF-8 length is never smaller than either a character count or a UTF-16
/// code-unit count - so a value that fits here fits the rule whichever unit
/// `size()` turns out to count. Counting characters instead would let a name
/// of multi-byte characters pass the form and then be refused by Firestore,
/// which is the exact failure this file exists to prevent.
class TextLimits {
  const TextLimits._();

  /// Mirrors `isValidProfile` in firestore.rules: `name.size() <= 100`.
  static const int profileName = 100;

  /// Mirrors `isNutrition` in firestore.rules: `foodName.size() <= 200`.
  ///
  /// One cap covers every copy of the name: a meal document stores it at the
  /// top level and again inside both nutrition blocks, all from the same
  /// string, and the nested ones are what the rules measure.
  static const int foodName = 200;

  /// The app's own bound - no security rule constrains a description.
  ///
  /// A description is a sentence or two about a plate of food, so this is
  /// several times what one needs and nowhere near anything Firestore would
  /// object to. It is here so a stored description cannot grow without limit,
  /// not to shape what somebody may write.
  static const int description = 1000;

  /// Whether [value] is short enough to store, measured as described above.
  static bool fits(String value, int maxLength) =>
      utf8.encode(value).length <= maxLength;

  /// The message for a [value] that is too long, or null when it fits.
  ///
  /// [label] begins the sentence, so callers pass it capitalised.
  static String? lengthError(
    String value, {
    required String label,
    required int maxLength,
  }) {
    if (fits(value, maxLength)) return null;

    // A character count is the honest wording for the ordinary case. When the
    // characters fit but the bytes do not, naming that number would only
    // confuse, so the message asks for something shorter instead.
    return value.length > maxLength
        ? '$label must be $maxLength characters or fewer'
        : '$label is too long. Please shorten it.';
  }
}
