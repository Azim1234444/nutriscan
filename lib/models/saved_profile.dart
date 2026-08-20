import 'user_profile.dart';

/// Field names used by the profile document.
///
/// Kept in one place so the security rules, the writer and the reader cannot
/// drift apart.
class ProfileFields {
  const ProfileFields._();

  static const String uid = 'uid';
  static const String name = 'name';
  static const String age = 'age';
  static const String gender = 'gender';
  static const String heightCm = 'heightCm';
  static const String weightKg = 'weightKg';
  static const String activityLevel = 'activityLevel';
  static const String goal = 'goal';

  // The targets the calculator produced when the profile was last saved.
  // Stored so another client can read them without recomputing.
  static const String dailyCalories = 'dailyCalories';
  static const String proteinGrams = 'proteinGrams';
  static const String carbohydratesGrams = 'carbohydratesGrams';
  static const String fatGrams = 'fatGrams';

  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
}

/// Sensible bounds for a stored profile, matching the setup form's validation.
class _Limits {
  const _Limits._();

  static const int minAge = 10;
  static const int maxAge = 100;
  static const double minHeightCm = 100;
  static const double maxHeightCm = 250;
  static const double minWeightKg = 30;
  static const double maxWeightKg = 300;
}

/// Builds the document body for [profile].
///
/// [targets] comes from the nutrition calculator - this layer never works out
/// calorie or macro numbers itself.
Map<String, Object?> profileToFirestore(
  UserProfile profile, {
  required String uid,
  required double dailyCalories,
  required double proteinGrams,
  required double carbohydratesGrams,
  required double fatGrams,
  required Object updatedAt,
  Object? createdAt,
}) {
  return <String, Object?>{
    ProfileFields.uid: uid,
    ProfileFields.name: profile.name,
    ProfileFields.age: profile.age,
    ProfileFields.gender: profile.gender.name,
    ProfileFields.heightCm: profile.heightCm,
    ProfileFields.weightKg: profile.weightKg,
    ProfileFields.activityLevel: profile.activityLevel.name,
    ProfileFields.goal: profile.goal.name,
    ProfileFields.dailyCalories: dailyCalories,
    ProfileFields.proteinGrams: proteinGrams,
    ProfileFields.carbohydratesGrams: carbohydratesGrams,
    ProfileFields.fatGrams: fatGrams,
    // Set once on create, then left alone by later saves.
    ProfileFields.createdAt: ?createdAt,
    ProfileFields.updatedAt: updatedAt,
  };
}

/// Rebuilds a [UserProfile] from a document.
///
/// Returns null when the document cannot be read - a malformed profile must
/// leave the app usable rather than crash it, and the user can simply fill the
/// form in again.
UserProfile? profileFromFirestore(Map<String, Object?>? data) {
  if (data == null) return null;

  final String? name = _stringAt(data, ProfileFields.name);
  final int? age = _intAt(
    data,
    ProfileFields.age,
    _Limits.minAge,
    _Limits.maxAge,
  );
  final double? heightCm = _amountAt(
    data,
    ProfileFields.heightCm,
    _Limits.minHeightCm,
    _Limits.maxHeightCm,
  );
  final double? weightKg = _amountAt(
    data,
    ProfileFields.weightKg,
    _Limits.minWeightKg,
    _Limits.maxWeightKg,
  );

  if (name == null || name.isEmpty) return null;
  if (age == null || heightCm == null || weightKg == null) return null;

  final Gender? gender = _enumByName(Gender.values, data[ProfileFields.gender]);
  final ActivityLevel? activityLevel = _enumByName(
    ActivityLevel.values,
    data[ProfileFields.activityLevel],
  );
  final NutritionGoal? goal = _enumByName(
    NutritionGoal.values,
    data[ProfileFields.goal],
  );

  if (gender == null || activityLevel == null || goal == null) return null;

  return UserProfile(
    name: name,
    age: age,
    gender: gender,
    heightCm: heightCm,
    weightKg: weightKg,
    activityLevel: activityLevel,
    goal: goal,
  );
}

String? _stringAt(Map<String, Object?> data, String field) {
  final Object? value = data[field];
  return value is String ? value.trim() : null;
}

int? _intAt(Map<String, Object?> data, String field, int min, int max) {
  final Object? value = data[field];
  if (value is! num || !value.isFinite) return null;
  final int parsed = value.round();
  if (parsed < min || parsed > max) return null;
  return parsed;
}

double? _amountAt(
  Map<String, Object?> data,
  String field,
  double min,
  double max,
) {
  final Object? value = data[field];
  if (value is! num || !value.isFinite) return null;
  final double parsed = value.toDouble();
  if (parsed < min || parsed > max) return null;
  return parsed;
}

/// Looks an enum up by its stored `name`, tolerating anything unexpected.
T? _enumByName<T extends Enum>(List<T> values, Object? stored) {
  for (final T value in values) {
    if (value.name == stored) return value;
  }
  return null;
}
