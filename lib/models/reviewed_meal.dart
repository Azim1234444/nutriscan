import 'food_analysis_result.dart';

/// A meal the user is reviewing, holding both versions of the numbers.
///
/// [aiEstimate] is what the model returned and never changes. [current] is
/// what the user has settled on - the same values until they edit something.
/// Keeping both means the app can always show, or later store, what the AI
/// originally said next to what the person corrected it to.
class ReviewedMeal {
  const ReviewedMeal({required this.aiEstimate, required this.current});

  /// Starts a review with the estimate exactly as the model returned it.
  ReviewedMeal.fromAnalysis(FoodAnalysisResult analysis)
    : aiEstimate = analysis,
      current = analysis;

  /// Untouched output of the model.
  final FoodAnalysisResult aiEstimate;

  /// What the result screen shows: the estimate plus any user corrections.
  final FoodAnalysisResult current;

  /// True once the user has changed at least one editable field.
  bool get isEdited => current.differsFrom(aiEstimate);

  /// Records a user correction, keeping the original estimate intact.
  ReviewedMeal withEdits(FoodAnalysisResult edited) {
    return ReviewedMeal(aiEstimate: aiEstimate, current: edited);
  }
}
