import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/services_scope.dart';
import '../../services/app_state.dart';
import '../../services/profile_repository.dart';
import '../../models/user_profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/formatters.dart';
import '../../utils/text_limits.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/option_chips.dart';
import '../../widgets/option_tile_group.dart';

/// Collects (or edits) the details NutriScan needs to calculate daily targets.
///
/// The same screen is used twice:
///  * first run, with [existingProfile] null - it then opens the dashboard
///  * editing from the profile tab - it then simply pops back
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.existingProfile});

  /// Profile to pre-fill the form with, or null when setting up for the first
  /// time.
  final UserProfile? existingProfile;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;

  /// True while the profile is being written.
  bool _isSaving = false;

  /// Why the last save failed, if it did.
  String? _saveError;

  /// The ages the app accepts, matching the bounds the security rules hold.
  static const int _minAge = 10;
  static const int _maxAge = 100;

  late Gender _gender;
  late ActivityLevel _activityLevel;
  late NutritionGoal _goal;

  bool get _isEditing => widget.existingProfile != null;

  @override
  void initState() {
    super.initState();
    final UserProfile? profile = widget.existingProfile;

    _nameController = TextEditingController(text: profile?.name ?? '');
    _ageController = TextEditingController(
      text: profile == null ? '' : profile.age.toString(),
    );
    _heightController = TextEditingController(
      text: profile == null ? '' : Formatters.measurement(profile.heightCm),
    );
    _weightController = TextEditingController(
      text: profile == null ? '' : Formatters.measurement(profile.weightKg),
    );

    _gender = profile?.gender ?? Gender.male;
    _activityLevel = profile?.activityLevel ?? ActivityLevel.moderate;
    _goal = profile?.goal ?? NutritionGoal.maintain;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  /// Saves the profile to Firestore, then to app state, then navigates.
  ///
  /// Nothing moves until the write succeeds: on failure the form keeps every
  /// value the user typed and shows a retryable error, so their input is never
  /// lost to a flaky connection.
  Future<void> _save() async {
    // Hide the keyboard so the user sees the result of saving.
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    // Read through the same helper the validator used, so there is no second
    // reading of the field to drift from the first.
    final int? age = _ageFrom(_ageController.text);
    if (age == null) {
      // Unreachable: the form validated first, and it accepts exactly what
      // this reads. Handled rather than asserted so that if the two ever come
      // apart again, the user is told something instead of tapping a button
      // that does nothing at all.
      setState(() => _saveError = 'Enter age as a whole number of years.');
      return;
    }

    final UserProfile profile = UserProfile(
      name: _nameController.text.trim(),
      age: age,
      gender: _gender,
      heightCm: double.parse(_heightController.text.trim()),
      weightKg: double.parse(_weightController.text.trim()),
      activityLevel: _activityLevel,
      goal: _goal,
    );

    final ProfileRepository profiles = ServicesScope.of(context)
        .profileRepository;
    final AppState appState = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      // Targets are recalculated inside the repository, from the one
      // calculator the whole app uses.
      if (_isEditing) {
        await profiles.updateProfile(profile);
      } else {
        await profiles.saveProfile(profile);
      }
    } on ProfileRepositoryFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = failure.message;
      });
      return;
    }

    if (!mounted) return;
    appState.saveProfile(profile);
    setState(() => _isSaving = false);

    if (_isEditing) {
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated')));
    } else {
      // First run: the dashboard replaces the whole navigation stack so the
      // user cannot swipe back into onboarding.
      navigator.pushNamedAndRemoveUntil(
        AppRoutes.home,
        (Route<dynamic> route) => false,
      );
    }
  }

  /// Checks the name field, in the same terms the save writes it.
  ///
  /// Trimmed first, because a trimmed name is what is stored. The maximum is
  /// the one the security rules hold, checked here so a long name is refused
  /// by the form with wording that explains it, instead of by Firestore with
  /// a permission error that does not.
  String? _validateName(String? value) {
    final String name = value?.trim() ?? '';
    if (name.isEmpty) return 'Please enter your name';

    return TextLimits.lengthError(
      name,
      label: 'Name',
      maxLength: TextLimits.profileName,
    );
  }

  /// The one definition of an age this form accepts: whole years, in range.
  ///
  /// Returns null for anything else. Both the validator and the save path ask
  /// through here, which is what stops the form accepting a value the save
  /// cannot read - the two used to disagree, and a decimal age slipped between
  /// them into an `int.parse` that threw.
  ///
  /// Deliberately `int.tryParse`, not `double`: an age is counted in whole
  /// years, so "28.5" is not a valid age rather than one to be rounded.
  static int? _ageFrom(String? value) {
    final int? years = int.tryParse(value?.trim() ?? '');
    if (years == null || years < _minAge || years > _maxAge) return null;
    return years;
  }

  /// Checks the age field, in the same terms [_ageFrom] reads it.
  String? _validateAge(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return 'Please enter your age';
    // Said separately from the range, because "28.5" is not out of range - it
    // is the wrong kind of number, and saying so is what tells the user to
    // drop the decimal rather than pick a different age.
    if (int.tryParse(text) == null) {
      return 'Enter age as a whole number of years';
    }
    if (_ageFrom(text) == null) {
      return 'age should be between $_minAge and $_maxAge';
    }
    return null;
  }

  /// Shared number check for height and weight, which may be fractional.
  String? _validateNumber(
    String? value, {
    required String field,
    required double min,
    required double max,
  }) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your $field';
    }
    final double? parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Enter $field as a number';
    if (parsed < min || parsed > max) {
      return '$field should be between ${Formatters.measurement(min)} and '
          '${Formatters.measurement(max)}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit profile' : 'Your profile'),
        automaticallyImplyLeading: _isEditing,
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
              if (!_isEditing) ...<Widget>[
                Text('Tell us about yourself', style: text.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'NutriScan uses these details to estimate the calories and '
                  'macros you need each day.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
              ],

              AppTextField(
                label: 'Name',
                controller: _nameController,
                hintText: 'e.g. Alex Carter',
                validator: _validateName,
              ),
              const SizedBox(height: AppSpacing.lg),

              AppTextField(
                label: 'Age',
                controller: _ageController,
                hintText: 'e.g. 28',
                suffixText: 'years',
                isNumeric: true,
                validator: _validateAge,
              ),
              const SizedBox(height: AppSpacing.lg),

              OptionChips<Gender>(
                label: 'Gender',
                options: Gender.values,
                selected: _gender,
                labelBuilder: (Gender option) => option.label,
                onSelected: (Gender option) => setState(() => _gender = option),
              ),
              const SizedBox(height: AppSpacing.lg),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: AppTextField(
                      label: 'Height (cm)',
                      controller: _heightController,
                      hintText: '175',
                      suffixText: 'cm',
                      isNumeric: true,
                      validator: (String? value) => _validateNumber(
                        value,
                        field: 'height',
                        min: 100,
                        max: 250,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppTextField(
                      label: 'Weight (kg)',
                      controller: _weightController,
                      hintText: '70',
                      suffixText: 'kg',
                      isNumeric: true,
                      textInputAction: TextInputAction.done,
                      validator: (String? value) => _validateNumber(
                        value,
                        field: 'weight',
                        min: 30,
                        max: 300,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              OptionTileGroup<ActivityLevel>(
                label: 'Activity level',
                options: ActivityLevel.values,
                selected: _activityLevel,
                titleBuilder: (ActivityLevel option) => option.label,
                descriptionBuilder: (ActivityLevel option) =>
                    option.description,
                onSelected: (ActivityLevel option) =>
                    setState(() => _activityLevel = option),
              ),
              const SizedBox(height: AppSpacing.lg),

              OptionTileGroup<NutritionGoal>(
                label: 'Goal',
                options: NutritionGoal.values,
                selected: _goal,
                titleBuilder: (NutritionGoal option) => option.label,
                descriptionBuilder: (NutritionGoal option) =>
                    option.description,
                onSelected: (NutritionGoal option) =>
                    setState(() => _goal = option),
              ),
            ],
          ),
        ),
      ),
      // A Scaffold pins its bottom bar to the bottom of the screen, which the
      // on-screen keyboard would cover. Adding the keyboard height as padding
      // keeps the save button visible while the user is typing.
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
                if (_saveError != null) ...<Widget>[
                  _SaveErrorNotice(message: _saveError!),
                  const SizedBox(height: AppSpacing.md),
                ],
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _saveError != null
                              ? 'Try again'
                              : _isEditing
                              ? 'Save changes'
                              : 'Continue',
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains a failed profile save, right above the button that retries it.
class _SaveErrorNotice extends StatelessWidget {
  const _SaveErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: AppColors.danger,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: text.bodySmall?.copyWith(color: AppColors.danger),
          ),
        ),
      ],
    );
  }
}
