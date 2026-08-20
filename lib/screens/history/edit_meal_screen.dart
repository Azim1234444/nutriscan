import 'package:flutter/material.dart';

import '../../app/services_scope.dart';
import '../../models/food_analysis_result.dart';
import '../../models/food_entry.dart';
import '../../models/saved_meal.dart';
import '../../services/meal_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/formatters.dart';
import '../../utils/nutrition_validators.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/option_chips.dart';

/// Corrects a meal that is already in the user's history.
///
/// The same form as the one used while reviewing a fresh scan, with the meal
/// type added - by then the app has guessed it from the clock, and the guess
/// is sometimes wrong. Saving writes to the meal's own document, so the meal
/// keeps its id, its place in history and the AI's original estimate.
///
/// Pops with true once the change is stored, and with nothing if the user
/// backs out.
class EditMealScreen extends StatefulWidget {
  const EditMealScreen({super.key, required this.meal});

  final SavedMeal meal;

  @override
  State<EditMealScreen> createState() => _EditMealScreenState();
}

class _EditMealScreenState extends State<EditMealScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _portionController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  late final TextEditingController _fiberController;

  late MealType _mealType;

  /// True while the change is being written.
  bool _isSaving = false;

  /// Why the last attempt failed, if it did.
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final FoodAnalysisResult current = widget.meal.current;

    _nameController = TextEditingController(text: current.foodName);
    _descriptionController = TextEditingController(text: current.description);
    _portionController = _amountController(current.portionGrams);
    _caloriesController = _amountController(current.calories);
    _proteinController = _amountController(current.proteinG);
    _carbsController = _amountController(current.carbsG);
    _fatController = _amountController(current.fatG);
    _fiberController = _amountController(current.fiberG);
    _mealType = widget.meal.mealType;
  }

  TextEditingController _amountController(double value) {
    return TextEditingController(text: Formatters.measurement(value));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _portionController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _fiberController.dispose();
    super.dispose();
  }

  /// Validates, writes the correction, then returns to the list.
  ///
  /// Nothing happens while a write is already in flight, so repeated taps on
  /// Save cannot produce two writes.
  Future<void> _save() async {
    if (_isSaving) return;

    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final MealRepository repository = ServicesScope.of(context).mealRepository;
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // withEdits keeps the id, the creation time and the AI estimate, and
    // works isEdited out by comparing the two sets of numbers.
    final SavedMeal updated = widget.meal.withEdits(
      widget.meal.current.copyWith(
        foodName: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        portionGrams: _amount(_portionController),
        calories: _amount(_caloriesController),
        proteinG: _amount(_proteinController),
        carbsG: _amount(_carbsController),
        fatG: _amount(_fatController),
        fiberG: _amount(_fiberController),
      ),
      mealType: _mealType,
    );

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      await repository.updateMeal(updated);
    } on MealRepositoryFailure catch (error) {
      // The form stays open with the user's numbers in it, ready to retry.
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = error.message;
      });
      return;
    }

    // The change is stored, but this screen may not be here to report it: the
    // system back gesture is not blocked while a write runs, so the user can
    // leave mid-save. Popping anyway would take out whatever route is on top
    // by then - the tabbed shell this screen was opened from - and leave the
    // app on an empty stack. History re-reads the day whenever the editor
    // closes, however it closed, so the edit still shows.
    if (!mounted) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Meal updated')));
    navigator.pop(true);
  }

  /// Discards every change.
  void _cancel() {
    if (_isSaving) return;
    Navigator.of(context).pop();
  }

  double _amount(TextEditingController controller) {
    return double.parse(controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit meal'),
        leading: IconButton(
          onPressed: _cancel,
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: <Widget>[
              Text(
                'Correct anything that is wrong. The meal keeps its place in '
                'your history, and the AI estimate is kept as it was.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),

              _AiEstimateCard(estimate: widget.meal.aiEstimate),
              const SizedBox(height: AppSpacing.xl),

              AppTextField(
                label: 'Food name',
                controller: _nameController,
                hintText: 'e.g. Grilled chicken salad',
                validator: NutritionValidators.foodName,
              ),
              const SizedBox(height: AppSpacing.lg),

              AppTextField(
                label: 'Description',
                controller: _descriptionController,
                hintText: 'e.g. Mixed leaves with grilled chicken',
                validator: NutritionValidators.description,
              ),
              const SizedBox(height: AppSpacing.lg),

              OptionChips<MealType>(
                label: 'Meal',
                options: MealType.values,
                selected: _mealType,
                labelBuilder: (MealType option) => option.label,
                onSelected: (MealType option) =>
                    setState(() => _mealType = option),
              ),
              const SizedBox(height: AppSpacing.lg),

              AppTextField(
                label: 'Portion (g)',
                controller: _portionController,
                suffixText: 'g',
                isNumeric: true,
                validator: (String? value) => NutritionValidators.amount(
                  value,
                  field: 'portion',
                  mustBePositive: true,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              AppTextField(
                label: 'Calories (kcal)',
                controller: _caloriesController,
                suffixText: 'kcal',
                isNumeric: true,
                validator: (String? value) =>
                    NutritionValidators.amount(value, field: 'calories'),
              ),
              const SizedBox(height: AppSpacing.lg),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: AppTextField(
                      label: 'Protein (g)',
                      controller: _proteinController,
                      suffixText: 'g',
                      isNumeric: true,
                      validator: (String? value) =>
                          NutritionValidators.amount(value, field: 'protein'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppTextField(
                      label: 'Carbs (g)',
                      controller: _carbsController,
                      suffixText: 'g',
                      isNumeric: true,
                      validator: (String? value) => NutritionValidators.amount(
                        value,
                        field: 'carbohydrates',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: AppTextField(
                      label: 'Fat (g)',
                      controller: _fatController,
                      suffixText: 'g',
                      isNumeric: true,
                      validator: (String? value) =>
                          NutritionValidators.amount(value, field: 'fat'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppTextField(
                      label: 'Fibre (g)',
                      controller: _fiberController,
                      suffixText: 'g',
                      isNumeric: true,
                      textInputAction: TextInputAction.done,
                      validator: (String? value) =>
                          NutritionValidators.amount(value, field: 'fibre'),
                    ),
                  ),
                ],
              ),

              if (_saveError != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                _SaveErrorCard(message: _saveError!),
              ],
            ],
          ),
        ),
      ),
      // A Scaffold pins its bottom bar to the bottom of the screen, which the
      // keyboard would cover, so the keyboard height is added as padding.
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.outline)),
          ),
          child: SafeArea(
            minimum: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FilledButton(
                  // Disabled while saving, so the write cannot be started a
                  // second time.
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Changes'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _isSaving ? null : _cancel,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the model originally said, so a correction is made with the estimate
/// in view rather than against a blank.
class _AiEstimateCard extends StatelessWidget {
  const _AiEstimateCard({required this.estimate});

  final FoodAnalysisResult estimate;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      color: AppColors.primarySoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'AI estimate',
            style: text.titleSmall?.copyWith(color: AppColors.primaryDark),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${estimate.foodName} · '
            '${Formatters.calories(estimate.calories)} kcal · '
            '${Formatters.grams(estimate.portionGrams)}',
            style: text.bodyMedium?.copyWith(color: AppColors.primaryDark),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Kept exactly as it was. Your changes are stored alongside it.',
            style: text.bodySmall?.copyWith(color: AppColors.primaryDark),
          ),
        ],
      ),
    );
  }
}

/// Explains a failed write and leaves the form ready to try again.
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
                Text('Changes not saved', style: text.titleMedium),
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
