import '../utils/text_limits.dart';
import 'nutrition_summary.dart';

/// One component the model recognised in the photo, e.g. "Grilled chicken".
class AnalyzedFoodItem {
  const AnalyzedFoodItem({required this.name, required this.portionGrams});

  final String name;
  final double portionGrams;

  factory AnalyzedFoodItem.fromJson(Map<String, Object?> json) {
    return AnalyzedFoodItem(
      name: _readString(json, 'name'),
      portionGrams: _readNumber(json, 'estimated_portion_grams'),
    );
  }
}

/// A nutrition estimate produced by the backend for one photo.
///
/// Every value is an AI estimate, never a measured figure - screens showing
/// these numbers must say so.
class FoodAnalysisResult {
  const FoodAnalysisResult({
    required this.foodName,
    required this.description,
    required this.portionGrams,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.confidence,
    required this.assumptions,
    required this.items,
  });

  final String foodName;
  final String description;
  final double portionGrams;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;

  /// The model's own certainty, from 0 to 1.
  final double confidence;

  /// What the model had to guess, e.g. an unseen portion weight.
  final List<String> assumptions;

  final List<AnalyzedFoodItem> items;

  /// The macro totals in the shape the rest of the app already uses.
  NutritionSummary get nutrition => NutritionSummary(
    calories: calories,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
  );

  /// Plain-language reading of [confidence], for a label next to the meter.
  String get confidenceLabel {
    if (confidence >= 0.75) return 'High confidence';
    if (confidence >= 0.5) return 'Moderate confidence';
    return 'Low confidence';
  }

  /// Returns a copy with the user-editable fields replaced.
  ///
  /// Only the fields a person can correct are parameters here. [confidence],
  /// [assumptions] and [items] come from the model and are carried over
  /// untouched - a human edit says nothing about how sure the model was.
  FoodAnalysisResult copyWith({
    String? foodName,
    String? description,
    double? portionGrams,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fiberG,
  }) {
    return FoodAnalysisResult(
      foodName: foodName ?? this.foodName,
      description: description ?? this.description,
      portionGrams: portionGrams ?? this.portionGrams,
      calories: calories ?? this.calories,
      proteinG: proteinG ?? this.proteinG,
      carbsG: carbsG ?? this.carbsG,
      fatG: fatG ?? this.fatG,
      fiberG: fiberG ?? this.fiberG,
      confidence: confidence,
      assumptions: assumptions,
      items: items,
    );
  }

  /// True when any editable field differs from [other].
  ///
  /// Used to tell an untouched AI estimate from one a person has corrected.
  bool differsFrom(FoodAnalysisResult other) {
    return foodName != other.foodName ||
        description != other.description ||
        portionGrams != other.portionGrams ||
        calories != other.calories ||
        proteinG != other.proteinG ||
        carbsG != other.carbsG ||
        fatG != other.fatG ||
        fiberG != other.fiberG;
  }

  /// Builds a result from the callable's JSON.
  ///
  /// Throws [FormatException] if a field is missing or the wrong type, so a
  /// half-parsed estimate can never reach the UI.
  factory FoodAnalysisResult.fromJson(Map<String, Object?> json) {
    final Object? rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('items must be a list');
    }

    final Object? rawAssumptions = json['assumptions'];
    if (rawAssumptions is! List) {
      throw const FormatException('assumptions must be a list');
    }

    return FoodAnalysisResult(
      // Bounded, because the two strings the model writes are the two that
      // get stored. The prompt asks for a short name and a sentence or two,
      // but nothing enforces that, and an over-long one would sail through
      // here and be refused by Firestore.
      foodName: _readStorableString(json, 'food_name', TextLimits.foodName),
      description: _readStorableString(
        json,
        'description',
        TextLimits.description,
      ),
      portionGrams: _readNumber(json, 'estimated_portion_grams'),
      calories: _readNumber(json, 'calories'),
      proteinG: _readNumber(json, 'protein_grams'),
      carbsG: _readNumber(json, 'carbohydrates_grams'),
      fatG: _readNumber(json, 'fat_grams'),
      fiberG: _readNumber(json, 'fiber_grams'),
      confidence: _readNumber(json, 'confidence').clamp(0, 1).toDouble(),
      assumptions: rawAssumptions
          .whereType<String>()
          .where((String line) => line.trim().isNotEmpty)
          .toList(),
      items: rawItems
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) =>
                AnalyzedFoodItem.fromJson(item.cast<String, Object?>()),
          )
          .toList(),
    );
  }
}

String _readString(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value is! String) {
    throw FormatException('$field must be a string');
  }
  return value;
}

/// Reads a model string that the app will go on to store.
///
/// Trimmed, then held to the length the store will accept. Rejecting here
/// turns an unusable estimate into an ordinary "unexpected format" failure,
/// which the scan screen already knows how to show and the user can retry -
/// rather than letting it reach Firestore and come back as a permission
/// error, which describes nothing that is actually wrong.
String _readStorableString(
  Map<String, Object?> json,
  String field,
  int maxLength,
) {
  final String value = _readString(json, field).trim();
  if (!TextLimits.fits(value, maxLength)) {
    throw FormatException('$field is longer than $maxLength bytes');
  }
  return value;
}

double _readNumber(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value is! num || !value.isFinite) {
    throw FormatException('$field must be a number');
  }
  return value.toDouble();
}
