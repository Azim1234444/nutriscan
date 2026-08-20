// Unit tests for the daily target maths.

import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/models/nutrition_summary.dart';
import 'package:nutriscan/models/user_profile.dart';
import 'package:nutriscan/services/nutrition_calculator.dart';

void main() {
  const UserProfile profile = UserProfile(
    name: 'Alex Carter',
    age: 28,
    gender: Gender.male,
    heightCm: 175,
    weightKg: 70,
    activityLevel: ActivityLevel.moderate,
    goal: NutritionGoal.maintain,
  );

  test('falls back to default targets when there is no profile', () {
    expect(
      NutritionCalculator.targetsFor(null).calories,
      NutritionCalculator.defaultTargets.calories,
    );
  });

  test('a weight loss goal targets fewer calories than maintaining', () {
    final NutritionSummary maintain = NutritionCalculator.targetsFor(profile);
    final NutritionSummary lose = NutritionCalculator.targetsFor(
      profile.copyWith(goal: NutritionGoal.lose),
    );

    expect(lose.calories, lessThan(maintain.calories));
  });

  test('macro targets are positive and sensible', () {
    final NutritionSummary targets = NutritionCalculator.targetsFor(profile);

    expect(targets.calories, greaterThan(1500));
    expect(targets.proteinG, greaterThan(0));
    expect(targets.carbsG, greaterThan(0));
    expect(targets.fatG, greaterThan(0));
  });
}
