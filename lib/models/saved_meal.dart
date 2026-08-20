import 'food_analysis_result.dart';
import 'food_entry.dart';
import 'reviewed_meal.dart';

/// A meal stored in Firestore under `users/{uid}/meals/{mealId}`.
///
/// Keeps both versions of the numbers: [aiEstimate] as the model produced it,
/// and [current] as the user left it. Only [current] counts towards totals.
class SavedMeal {
  const SavedMeal({
    required this.id,
    required this.userId,
    required this.mealType,
    required this.aiEstimate,
    required this.current,
    required this.isEdited,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final MealType mealType;

  /// The model's original estimate, kept for reference.
  final FoodAnalysisResult aiEstimate;

  /// The values the user accepted - what the app displays and totals.
  final FoodAnalysisResult current;

  final bool isEdited;

  /// When the meal was saved, in local time. An edit never changes this, so
  /// a corrected meal stays on the day it was eaten.
  final DateTime createdAt;

  /// When the meal was last corrected, in local time.
  ///
  /// Null for a meal nobody has edited, and for documents written before the
  /// field existed.
  final DateTime? updatedAt;

  /// Applies a correction, keeping everything that is not the user's to
  /// change.
  ///
  /// [aiEstimate], [id] and [createdAt] are carried over untouched.
  /// [isEdited] is not passed in: it is worked out by comparing the new
  /// values with the model's, so restoring a meal to the AI numbers clears
  /// the flag exactly as making it differ sets it.
  SavedMeal withEdits(FoodAnalysisResult edited, {MealType? mealType}) {
    return SavedMeal(
      id: id,
      userId: userId,
      mealType: mealType ?? this.mealType,
      aiEstimate: aiEstimate,
      current: edited,
      isEdited: edited.differsFrom(aiEstimate),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Renders this meal with the meal cards the app already uses.
  FoodEntry toFoodEntry() {
    return FoodEntry(
      id: id,
      name: current.foodName,
      loggedAt: createdAt,
      mealType: mealType,
      servingLabel: '${current.portionGrams.round()} g',
      nutrition: current.nutrition,
    );
  }

  /// Picks a meal type from the time of day.
  ///
  /// The app does not ask the user which meal this is, so the clock is the
  /// best available guess.
  static MealType mealTypeForTime(DateTime time) {
    final int hour = time.hour;
    if (hour < 11) return MealType.breakfast;
    if (hour < 15) return MealType.lunch;
    if (hour < 21) return MealType.dinner;
    return MealType.snack;
  }
}

/// Field names used in Firestore. Kept in one place so the rules, the writer
/// and the reader cannot drift apart.
class MealFields {
  const MealFields._();

  static const String userId = 'userId';
  static const String foodName = 'foodName';
  static const String description = 'description';
  static const String mealType = 'mealType';
  static const String portionGrams = 'estimatedPortionGrams';
  static const String aiEstimate = 'aiEstimate';
  static const String current = 'current';
  static const String isEdited = 'isEdited';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';

  // Nested nutrition keys.
  static const String calories = 'calories';
  static const String protein = 'proteinGrams';
  static const String carbs = 'carbohydratesGrams';
  static const String fat = 'fatGrams';
  static const String fiber = 'fiberGrams';
  static const String confidence = 'confidence';
  static const String assumptions = 'assumptions';
  static const String items = 'items';
  static const String itemName = 'name';
}

/// Builds the document body for a reviewed meal.
///
/// The photo is deliberately absent: images are not stored in this phase, and
/// never as base64 in a document.
///
/// [createdAt] is left out when null, which is how a re-save of a meal that is
/// already stored keeps the day it was logged on. Only the first write of a
/// document sets it.
Map<String, Object?> mealToDocument(
  ReviewedMeal meal, {
  required String userId,
  required MealType mealType,
  required Object updatedAt,
  Object? createdAt,
}) {
  final FoodAnalysisResult current = meal.current;

  return <String, Object?>{
    MealFields.userId: userId,
    MealFields.foodName: current.foodName,
    MealFields.description: current.description,
    MealFields.mealType: mealType.name,
    MealFields.portionGrams: current.portionGrams,
    MealFields.aiEstimate: _aiEstimateToMap(meal.aiEstimate),
    MealFields.current: _currentToMap(current),
    MealFields.isEdited: meal.isEdited,
    // Set once, on the write that creates the document.
    MealFields.createdAt: ?createdAt,
    MealFields.updatedAt: updatedAt,
  };
}

/// Builds the body of an edit to a meal that is already stored.
///
/// Deliberately shorter than [mealToDocument]. It carries only what a person
/// is allowed to change, so the fields left out - `userId`, `aiEstimate` and
/// `createdAt` - cannot be altered by editing a meal even by mistake: there
/// is no code path that writes them. Merged into the existing document, so
/// everything absent here keeps the value it already had.
Map<String, Object?> mealEditToDocument(
  SavedMeal meal, {
  required Object updatedAt,
}) {
  final FoodAnalysisResult current = meal.current;

  return <String, Object?>{
    MealFields.foodName: current.foodName,
    MealFields.description: current.description,
    MealFields.mealType: meal.mealType.name,
    MealFields.portionGrams: current.portionGrams,
    MealFields.current: _currentToMap(current),
    MealFields.isEdited: meal.isEdited,
    MealFields.updatedAt: updatedAt,
  };
}

Map<String, Object?> _aiEstimateToMap(FoodAnalysisResult result) {
  return <String, Object?>{
    MealFields.foodName: result.foodName,
    MealFields.description: result.description,
    MealFields.portionGrams: result.portionGrams,
    MealFields.calories: result.calories,
    MealFields.protein: result.proteinG,
    MealFields.carbs: result.carbsG,
    MealFields.fat: result.fatG,
    MealFields.fiber: result.fiberG,
    MealFields.confidence: result.confidence,
    MealFields.assumptions: result.assumptions,
    MealFields.items: result.items
        .map(
          (AnalyzedFoodItem item) => <String, Object?>{
            MealFields.itemName: item.name,
            MealFields.portionGrams: item.portionGrams,
          },
        )
        .toList(),
  };
}

/// The user-facing values only: confidence and assumptions describe the AI's
/// work, so they stay on [MealFields.aiEstimate].
Map<String, Object?> _currentToMap(FoodAnalysisResult result) {
  return <String, Object?>{
    MealFields.foodName: result.foodName,
    MealFields.description: result.description,
    MealFields.portionGrams: result.portionGrams,
    MealFields.calories: result.calories,
    MealFields.protein: result.proteinG,
    MealFields.carbs: result.carbsG,
    MealFields.fat: result.fatG,
    MealFields.fiber: result.fiberG,
  };
}

/// Rebuilds a meal from a document.
///
/// Returns null when the document cannot be read - a single bad document must
/// never blank out the whole history.
SavedMeal? mealFromDocument(
  String id,
  Map<String, Object?>? data, {
  DateTime? fallbackCreatedAt,
}) {
  if (data == null) return null;

  final Map<String, Object?>? aiMap = _mapAt(data, MealFields.aiEstimate);
  final Map<String, Object?>? currentMap = _mapAt(data, MealFields.current);
  if (aiMap == null || currentMap == null) return null;

  final FoodAnalysisResult? aiEstimate = _resultFromMap(aiMap);
  if (aiEstimate == null) return null;

  // The user-edited copy carries no confidence or assumptions of its own -
  // those belong to the model, so they are read from the AI estimate.
  final FoodAnalysisResult? current = _resultFromMap(
    currentMap,
    confidence: aiEstimate.confidence,
    assumptions: aiEstimate.assumptions,
    items: aiEstimate.items,
  );
  if (current == null) return null;

  final DateTime? createdAt = _dateFrom(data[MealFields.createdAt]);

  return SavedMeal(
    id: id,
    userId: _stringAt(data, MealFields.userId) ?? '',
    mealType: _mealTypeFrom(data[MealFields.mealType]),
    aiEstimate: aiEstimate,
    current: current,
    isEdited: data[MealFields.isEdited] == true,
    // A server timestamp is null for a moment after a local write, so the
    // meal shows with the local time until the server value arrives.
    createdAt: createdAt ?? fallbackCreatedAt ?? DateTime.now(),
    updatedAt: _dateFrom(data[MealFields.updatedAt]),
  );
}

Map<String, Object?>? _mapAt(Map<String, Object?> data, String key) {
  final Object? value = data[key];
  if (value is Map) return Map<String, Object?>.from(value);
  return null;
}

String? _stringAt(Map<String, Object?> data, String key) {
  final Object? value = data[key];
  return value is String ? value : null;
}

double? _amountAt(Map<String, Object?> data, String key) {
  final Object? value = data[key];
  if (value is num && value.isFinite && value >= 0) return value.toDouble();
  return null;
}

MealType _mealTypeFrom(Object? value) {
  for (final MealType type in MealType.values) {
    if (type.name == value) return type;
  }
  return MealType.snack;
}

/// Accepts a Firestore `Timestamp`, a `DateTime`, or epoch milliseconds.
DateTime? _dateFrom(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  }
  // Firestore's Timestamp, matched by shape so this file stays plugin-free.
  try {
    final dynamic timestamp = value;
    final Object? converted = timestamp.toDate();
    if (converted is DateTime) return converted.toLocal();
  } catch (_) {
    // Not a timestamp - fall through.
  }
  return null;
}

FoodAnalysisResult? _resultFromMap(
  Map<String, Object?> map, {
  double? confidence,
  List<String>? assumptions,
  List<AnalyzedFoodItem>? items,
}) {
  final String? foodName = _stringAt(map, MealFields.foodName);
  final double? calories = _amountAt(map, MealFields.calories);
  final double? portion = _amountAt(map, MealFields.portionGrams);
  if (foodName == null || foodName.isEmpty || calories == null) return null;

  return FoodAnalysisResult(
    foodName: foodName,
    description: _stringAt(map, MealFields.description) ?? '',
    portionGrams: portion ?? 0,
    calories: calories,
    proteinG: _amountAt(map, MealFields.protein) ?? 0,
    carbsG: _amountAt(map, MealFields.carbs) ?? 0,
    fatG: _amountAt(map, MealFields.fat) ?? 0,
    fiberG: _amountAt(map, MealFields.fiber) ?? 0,
    confidence: confidence ?? _amountAt(map, MealFields.confidence) ?? 0,
    assumptions: assumptions ?? _stringListAt(map, MealFields.assumptions),
    items: items ?? _itemsAt(map),
  );
}

List<String> _stringListAt(Map<String, Object?> map, String key) {
  final Object? value = map[key];
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList();
}

List<AnalyzedFoodItem> _itemsAt(Map<String, Object?> map) {
  final Object? value = map[MealFields.items];
  if (value is! List) return const <AnalyzedFoodItem>[];

  return value
      .whereType<Map<Object?, Object?>>()
      .map((Map<Object?, Object?> raw) {
        final Map<String, Object?> item = Map<String, Object?>.from(raw);
        return AnalyzedFoodItem(
          name: _stringAt(item, MealFields.itemName) ?? '',
          portionGrams: _amountAt(item, MealFields.portionGrams) ?? 0,
        );
      })
      .where((AnalyzedFoodItem item) => item.name.isNotEmpty)
      .toList();
}
