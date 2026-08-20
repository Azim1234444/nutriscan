import 'package:flutter/material.dart';

import '../../models/food_analysis_result.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/formatters.dart';
import '../../utils/nutrition_validators.dart';
import '../../widgets/app_text_field.dart';

/// Lets the user correct the numbers the model estimated.
///
/// Pops with the corrected [FoodAnalysisResult], or with null if the user
/// cancels. Confidence, assumptions and the recognised items are not editable
/// here: they describe what the model did, not what the meal is.
class EditNutritionScreen extends StatefulWidget {
  const EditNutritionScreen({super.key, required this.result});

  /// The values the form starts from - the current estimate, edits included.
  final FoodAnalysisResult result;

  @override
  State<EditNutritionScreen> createState() => _EditNutritionScreenState();
}

class _EditNutritionScreenState extends State<EditNutritionScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _portionController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  late final TextEditingController _fiberController;

  @override
  void initState() {
    super.initState();
    final FoodAnalysisResult result = widget.result;

    _nameController = TextEditingController(text: result.foodName);
    _portionController = _amountController(result.portionGrams);
    _caloriesController = _amountController(result.calories);
    _proteinController = _amountController(result.proteinG);
    _carbsController = _amountController(result.carbsG);
    _fatController = _amountController(result.fatG);
    _fiberController = _amountController(result.fiberG);
  }

  TextEditingController _amountController(double value) {
    return TextEditingController(text: Formatters.measurement(value));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _portionController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _fiberController.dispose();
    super.dispose();
  }

  /// Validates, then returns the corrected result to the caller.
  void _save() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      widget.result.copyWith(
        foodName: _nameController.text.trim(),
        portionGrams: _amount(_portionController),
        calories: _amount(_caloriesController),
        proteinG: _amount(_proteinController),
        carbsG: _amount(_carbsController),
        fatG: _amount(_fatController),
        fiberG: _amount(_fiberController),
      ),
    );
  }

  /// Discards every change.
  void _cancel() => Navigator.of(context).pop();

  double _amount(TextEditingController controller) {
    return double.parse(controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit nutrition'),
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
                'Correct anything the estimate got wrong. The AI estimate is '
                'kept, so you can always see what it originally suggested.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),

              AppTextField(
                label: 'Food name',
                controller: _nameController,
                hintText: 'e.g. Grilled chicken salad',
                validator: NutritionValidators.foodName,
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
                  onPressed: _save,
                  child: const Text('Save Changes'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(onPressed: _cancel, child: const Text('Cancel')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
