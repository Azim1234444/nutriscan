/// Biological sex, used by the calorie formula.
enum Gender {
  male('Male'),
  female('Female'),
  other('Other');

  const Gender(this.label);

  final String label;
}

/// How much the user moves during a normal day.
///
/// [multiplier] is applied to the resting calorie burn to estimate the total
/// daily energy need.
enum ActivityLevel {
  sedentary('Sedentary', 'Little or no exercise', 1.2),
  light('Lightly active', 'Exercise 1-3 days a week', 1.375),
  moderate('Moderately active', 'Exercise 3-5 days a week', 1.55),
  active('Very active', 'Exercise 6-7 days a week', 1.725),
  athlete('Extra active', 'Physical job or training twice a day', 1.9);

  const ActivityLevel(this.label, this.description, this.multiplier);

  final String label;
  final String description;
  final double multiplier;
}

/// What the user wants their weight to do.
enum NutritionGoal {
  lose('Lose Weight', 'Gentle calorie deficit'),
  maintain('Maintain Weight', 'Stay at your current weight'),
  gain('Gain Weight', 'Steady calorie surplus');

  const NutritionGoal(this.label, this.description);

  final String label;
  final String description;
}

/// Everything NutriScan knows about the person using the app.
///
/// The model is immutable: to change a value, build a new copy with
/// [copyWith]. That keeps the app state predictable.
class UserProfile {
  const UserProfile({
    required this.name,
    required this.age,
    required this.gender,
    required this.heightCm,
    required this.weightKg,
    required this.activityLevel,
    required this.goal,
  });

  final String name;
  final int age;
  final Gender gender;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activityLevel;
  final NutritionGoal goal;

  /// Body Mass Index, shown on the profile screen.
  double get bmi {
    final double heightM = heightCm / 100;
    if (heightM <= 0) return 0;
    return weightKg / (heightM * heightM);
  }

  /// Short readable BMI category, e.g. "Normal".
  String get bmiCategory {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    return 'Obese';
  }

  /// First letters of the name, used for the avatar circle.
  String get initials {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'N';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  UserProfile copyWith({
    String? name,
    int? age,
    Gender? gender,
    double? heightCm,
    double? weightKg,
    ActivityLevel? activityLevel,
    NutritionGoal? goal,
  }) {
    return UserProfile(
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      activityLevel: activityLevel ?? this.activityLevel,
      goal: goal ?? this.goal,
    );
  }
}
