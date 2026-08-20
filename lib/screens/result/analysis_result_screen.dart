import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/services_scope.dart';
import '../../models/food_analysis_result.dart';
import '../../models/macro.dart';
import '../../models/reviewed_meal.dart';
import '../../services/app_state.dart';
import '../../services/meal_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/macro_visuals.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_card.dart';
import '../../widgets/edited_badge.dart';
import '../../widgets/section_header.dart';

/// Everything the result screen needs, passed as one route argument.
class AnalysisResultArgs {
  const AnalysisResultArgs({required this.image, required this.result});

  final File image;
  final FoodAnalysisResult result;
}

/// Shows the nutrition estimate for one photo and lets the user correct it.
///
/// The screen holds a [ReviewedMeal]: the model's original estimate plus the
/// user's edits. Every number shown is an estimate, and the disclaimer sits
/// directly under them so it is read together with the values.
class AnalysisResultScreen extends StatefulWidget {
  const AnalysisResultScreen({super.key, required this.args});

  final AnalysisResultArgs args;

  @override
  State<AnalysisResultScreen> createState() => _AnalysisResultScreenState();
}

class _AnalysisResultScreenState extends State<AnalysisResultScreen> {
  late ReviewedMeal _meal = ReviewedMeal.fromAnalysis(widget.args.result);

  /// True while the meal is being written.
  bool _isSaving = false;

  /// True once the meal is stored.
  bool _isSaved = false;

  /// Why the last save attempt failed, if it did.
  String? _saveError;

  /// The document this meal was written to.
  ///
  /// Kept so a retry overwrites that document rather than creating a second
  /// one, and so tapping Save twice can never duplicate the meal.
  String? _savedMealId;

  /// Opens the edit form and keeps whatever comes back.
  Future<void> _editNutrition() async {
    final FoodAnalysisResult? edited = await Navigator.of(context)
        .pushNamed<FoodAnalysisResult>(
          AppRoutes.editNutrition,
          arguments: _meal.current,
        );

    // Null means the user cancelled, so the current values stay as they were.
    if (edited == null || !mounted) return;

    setState(() {
      _meal = _meal.withEdits(edited);
      // The saved copy is now out of date, so allow saving again. The id is
      // kept, so saving updates that meal rather than adding another.
      _isSaved = false;
      _saveError = null;
    });
  }

  /// Saves the reviewed meal to the user's meal history.
  ///
  /// The meal is staged in app state first and only cleared once the write
  /// succeeds, so a failure leaves it available to retry. The document id is
  /// remembered, so retrying overwrites the same document instead of adding a
  /// second copy.
  Future<void> _saveMeal() async {
    if (_isSaving || _isSaved) return;

    final AppState state = AppScope.of(context);
    final MealRepository repository = ServicesScope.of(context).mealRepository;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    state.setPendingMeal(_meal);
    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      _savedMealId = await repository.saveMeal(_meal, mealId: _savedMealId);

      if (!mounted) return;
      state.clearPendingMeal();
      setState(() {
        _isSaving = false;
        _isSaved = true;
      });

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Meal saved')));
    } on MealRepositoryFailure catch (error) {
      // The pending meal stays put so the user can try again.
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final FoodAnalysisResult result = _meal.current;

    return Scaffold(
      appBar: AppBar(title: const Text('Analysis')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            ClipRRect(
              borderRadius: AppRadius.cardRadius,
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.file(
                  widget.args.image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: AppColors.primarySoft,
                    child: Icon(
                      Icons.restaurant_outlined,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(result.foodName, style: text.headlineSmall),
                ),
                if (_meal.isEdited) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  const EditedBadge(),
                ],
              ],
            ),
            if (result.description.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(result.description, style: text.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.lg),

            _CaloriesCard(meal: _meal),
            const SizedBox(height: AppSpacing.sm),
            _EstimateNotice(isEdited: _meal.isEdited),
            const SizedBox(height: AppSpacing.lg),

            const SectionHeader(title: 'Nutrients'),
            const SizedBox(height: AppSpacing.sm),
            _NutrientCard(result: result),
            const SizedBox(height: AppSpacing.lg),

            const SectionHeader(title: 'Confidence'),
            const SizedBox(height: AppSpacing.sm),
            _ConfidenceCard(result: result),

            if (result.items.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: 'What was recognised'),
              const SizedBox(height: AppSpacing.sm),
              _ItemsCard(items: result.items),
            ],

            if (result.assumptions.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: 'Assumptions'),
              const SizedBox(height: AppSpacing.sm),
              _AssumptionsCard(assumptions: result.assumptions),
            ],

            const SizedBox(height: AppSpacing.xl),
            if (_isSaved) ...<Widget>[
              const _SavedCard(),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_saveError != null) ...<Widget>[
              _SaveErrorCard(message: _saveError!),
              const SizedBox(height: AppSpacing.md),
            ],
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _editNutrition,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Nutrition'),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_isSaved)
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Done'),
              )
            else
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveMeal,
                icon: _isSaving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.bookmark_added_outlined),
                label: Text(
                  _isSaving
                      ? 'Saving…'
                      : _saveError != null
                      ? 'Try Again'
                      : 'Save Meal',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Confirms the meal is stored in the user's history.
class _SavedCard extends StatelessWidget {
  const _SavedCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      color: AppColors.primarySoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.check_circle_outline, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Meal saved',
                  style: text.titleMedium?.copyWith(
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'It is in your history and counts towards today\'s totals.',
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Explains a failed save and leaves the meal ready to try again.
class _SaveErrorCard extends StatelessWidget {
  const _SaveErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Meal not saved', style: text.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The headline number: calories for the whole portion.
class _CaloriesCard extends StatelessWidget {
  const _CaloriesCard({required this.meal});

  final ReviewedMeal meal;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final FoodAnalysisResult result = meal.current;
    final bool caloriesEdited = meal.aiEstimate.calories != result.calories;

    return AppCard(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  caloriesEdited ? 'Your calories' : 'Estimated calories',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      Formatters.calories(result.calories),
                      style: text.displaySmall?.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text('kcal', style: text.titleMedium),
                  ],
                ),
                // The model's own number stays visible after an edit.
                if (caloriesEdited)
                  Text(
                    'AI estimated '
                    '${Formatters.calories(meal.aiEstimate.calories)} kcal',
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '~${Formatters.grams(result.portionGrams)}',
              style: text.titleSmall?.copyWith(color: AppColors.primaryDark),
            ),
          ),
        ],
      ),
    );
  }
}

/// The estimate disclaimer, placed with the numbers rather than in a footer.
class _EstimateNotice extends StatelessWidget {
  const _EstimateNotice({required this.isEdited});

  final bool isEdited;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            isEdited
                ? 'Nutrition values are AI estimates and may not be exact. '
                      'Some values have been edited by you.'
                : 'Nutrition values are AI estimates and may not be exact.',
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Protein, carbs and fat in their usual colours, plus fibre.
class _NutrientCard extends StatelessWidget {
  const _NutrientCard({required this.result});

  final FoodAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: <Widget>[
          for (final Macro macro in Macro.values) ...<Widget>[
            _NutrientRow(
              color: MacroVisuals.color(macro),
              label: macro.label,
              grams: macro.valueIn(result.nutrition),
            ),
            const Divider(height: AppSpacing.xl),
          ],
          _NutrientRow(
            color: AppColors.primary,
            label: 'Fibre',
            grams: result.fiberG,
          ),
        ],
      ),
    );
  }
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({
    required this.color,
    required this.label,
    required this.grams,
  });

  final Color color;
  final String label;
  final double grams;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Container(
          height: 10,
          width: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: text.bodyLarge)),
        Text(Formatters.grams(grams), style: text.titleSmall),
      ],
    );
  }
}

/// How sure the model was, as a meter plus a plain-language label.
class _ConfidenceCard extends StatelessWidget {
  const _ConfidenceCard({required this.result});

  final FoodAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(result.confidenceLabel, style: text.titleMedium),
              ),
              Text(
                '${(result.confidence * 100).round()}%',
                style: text.titleMedium?.copyWith(color: AppColors.primaryDark),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: result.confidence,
              minHeight: 8,
              backgroundColor: AppColors.primarySoft,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The components the model picked out of the photo.
class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.items});

  final List<AnalyzedFoodItem> items;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        children: <Widget>[
          for (int index = 0; index < items.length; index++) ...<Widget>[
            if (index > 0) const Divider(height: AppSpacing.xl),
            Row(
              children: <Widget>[
                Expanded(child: Text(items[index].name, style: text.bodyLarge)),
                Text(
                  '~${Formatters.grams(items[index].portionGrams)}',
                  style: text.titleSmall,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// What the model had to guess to produce the numbers above.
class _AssumptionsCard extends StatelessWidget {
  const _AssumptionsCard({required this.assumptions});

  final List<String> assumptions;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final String assumption in assumptions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(assumption, style: text.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
