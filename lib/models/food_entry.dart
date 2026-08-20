import 'nutrition_summary.dart';

/// Which part of the day a meal belongs to.
enum MealType {
  breakfast('Breakfast'),
  lunch('Lunch'),
  dinner('Dinner'),
  snack('Snack');

  const MealType(this.label);

  final String label;
}

/// One scanned (for now: sample) food item in the user's history.
class FoodEntry {
  const FoodEntry({
    required this.id,
    required this.name,
    required this.loggedAt,
    required this.mealType,
    required this.servingLabel,
    required this.nutrition,
    this.emoji = '🍽️',
  });

  final String id;
  final String name;

  /// When the food was scanned.
  final DateTime loggedAt;
  final MealType mealType;

  /// Human readable portion, e.g. "1 bowl (250 g)".
  final String servingLabel;
  final NutritionSummary nutrition;

  /// Stand-in for the food photo until the camera is added in phase 2.
  final String emoji;

  double get calories => nutrition.calories;
  double get proteinG => nutrition.proteinG;
  double get carbsG => nutrition.carbsG;
  double get fatG => nutrition.fatG;
}
