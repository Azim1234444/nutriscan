/// A bundle of the four numbers NutriScan tracks.
///
/// The same type is used for daily targets and for what has been eaten so far,
/// which keeps the dashboard maths simple.
class NutritionSummary {
  const NutritionSummary({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  static const NutritionSummary zero = NutritionSummary(
    calories: 0,
    proteinG: 0,
    carbsG: 0,
    fatG: 0,
  );

  NutritionSummary operator +(NutritionSummary other) {
    return NutritionSummary(
      calories: calories + other.calories,
      proteinG: proteinG + other.proteinG,
      carbsG: carbsG + other.carbsG,
      fatG: fatG + other.fatG,
    );
  }

  /// Progress from 0.0 to 1.0 of [value] against [target].
  ///
  /// Clamped so a progress bar can never overflow its track.
  static double progress(double value, double target) {
    if (target <= 0) return 0;
    return (value / target).clamp(0.0, 1.0);
  }
}
