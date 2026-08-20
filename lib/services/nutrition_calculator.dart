import '../models/nutrition_summary.dart';
import '../models/user_profile.dart';

/// Turns a [UserProfile] into daily calorie and macro targets.
///
/// The formulas are the standard ones used by nutrition apps:
///  * Mifflin-St Jeor for the resting burn (BMR)
///  * BMR x activity multiplier for the total daily burn (TDEE)
///  * a fixed calorie offset for the weight goal
///
/// Nothing here talks to the network, so it stays valid for phase 1.
class NutritionCalculator {
  const NutritionCalculator._();

  /// Used before the user has filled in their profile.
  static const NutritionSummary defaultTargets = NutritionSummary(
    calories: 2000,
    proteinG: 120,
    carbsG: 240,
    fatG: 60,
  );

  static NutritionSummary targetsFor(UserProfile? profile) {
    if (profile == null) return defaultTargets;

    final double calories = _dailyCalories(profile);

    // Protein is set per kilogram of body weight, fat as a share of total
    // calories, and carbohydrates fill whatever energy is left over.
    final double proteinG = profile.weightKg * _proteinPerKg(profile.goal);
    final double fatG = (calories * 0.27) / 9;
    final double remainingCalories = calories - (proteinG * 4) - (fatG * 9);
    final double carbsG = (remainingCalories / 4).clamp(0, double.infinity);

    return NutritionSummary(
      calories: _roundTo(calories, 10),
      proteinG: _roundTo(proteinG, 1),
      carbsG: _roundTo(carbsG, 1),
      fatG: _roundTo(fatG, 1),
    );
  }

  /// Resting energy burn in calories per day (Mifflin-St Jeor).
  static double basalMetabolicRate(UserProfile profile) {
    final double base =
        (10 * profile.weightKg) + (6.25 * profile.heightCm) - (5 * profile.age);
    switch (profile.gender) {
      case Gender.male:
        return base + 5;
      case Gender.female:
        return base - 161;
      case Gender.other:
        // Midpoint of the male and female constants.
        return base - 78;
    }
  }

  static double _dailyCalories(UserProfile profile) {
    final double maintenance =
        basalMetabolicRate(profile) * profile.activityLevel.multiplier;
    switch (profile.goal) {
      case NutritionGoal.lose:
        return (maintenance - 500).clamp(1200, double.infinity);
      case NutritionGoal.maintain:
        return maintenance;
      case NutritionGoal.gain:
        return maintenance + 400;
    }
  }

  static double _proteinPerKg(NutritionGoal goal) {
    switch (goal) {
      case NutritionGoal.lose:
        return 2.0;
      case NutritionGoal.maintain:
        return 1.6;
      case NutritionGoal.gain:
        return 1.8;
    }
  }

  static double _roundTo(double value, int step) {
    return (value / step).round() * step.toDouble();
  }
}
