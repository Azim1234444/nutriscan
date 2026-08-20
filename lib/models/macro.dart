import 'nutrition_summary.dart';

/// The three macronutrients shown around the app.
///
/// Having them as an enum means the dashboard, history cards and macro chips
/// can all be built with the same loop instead of copy-pasted code.
enum Macro {
  protein('Protein'),
  carbs('Carbs'),
  fat('Fat');

  const Macro(this.label);

  final String label;

  /// Pulls this macro's value (in grams) out of a summary.
  double valueIn(NutritionSummary summary) {
    switch (this) {
      case Macro.protein:
        return summary.proteinG;
      case Macro.carbs:
        return summary.carbsG;
      case Macro.fat:
        return summary.fatG;
    }
  }
}
