// Tests for the Phase 2C review-and-edit flow.
//
// Nothing here touches the backend: the screens are driven with a fixed
// analysis result, which is exactly what the callable would have returned.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/food_analysis_result.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/screens/result/analysis_result_screen.dart';
import 'package:nutriscan/screens/result/edit_nutrition_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/meal_repository.dart';
import 'package:nutriscan/theme/app_theme.dart';

import 'support/test_doubles.dart';

/// Field order on the edit screen, top to bottom.
const int _nameField = 0;
const int _portionField = 1;
const int _caloriesField = 2;

/// The estimate the model returned, before any human correction.
final FoodAnalysisResult _aiResult = FoodAnalysisResult(
  foodName: 'Grilled chicken salad',
  description: 'Mixed leaves with sliced grilled chicken breast.',
  portionGrams: 320,
  calories: 580,
  proteinG: 42,
  carbsG: 18,
  fatG: 24,
  fiberG: 6,
  confidence: 0.85,
  assumptions: const <String>['Dressing assumed to be olive oil based.'],
  items: const <AnalyzedFoodItem>[
    AnalyzedFoodItem(name: 'Grilled chicken breast', portionGrams: 150),
  ],
);

void main() {
  // Real file I/O has to happen outside testWidgets: inside a test body the
  // fake async clock never completes disk operations.
  late Directory tempDirectory;
  late File mealPhoto;
  late AppState appState;
  late FakeMealRepository mealRepository;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp('nutriscan_result');
    mealPhoto = File('${tempDirectory.path}/meal.png');
    await mealPhoto.writeAsBytes(Uint8List.fromList(<int>[0x89, 0x50, 0x4E]));
  });

  tearDownAll(() async {
    await tempDirectory.delete(recursive: true);
  });

  setUp(() {
    appState = AppState();
  });

  tearDown(() {
    appState.dispose();
  });

  Future<void> pumpResultScreen(
    WidgetTester tester, {
    FakeMealRepository? repository,
  }) async {
    mealRepository = repository ?? FakeMealRepository();
    addTearDown(mealRepository.dispose);

    await tester.binding.setSurfaceSize(const Size(500, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ServicesScope(
        authService: FakeAuthService(),
        mealRepository: mealRepository,
        profileRepository: FakeProfileRepository(),
        child: AppScope(
          state: appState,
          child: MaterialApp(
            theme: AppTheme.light,
            onGenerateRoute: AppRoutes.onGenerateRoute,
            home: AnalysisResultScreen(
              key: UniqueKey(),
              args: AnalysisResultArgs(image: mealPhoto, result: _aiResult),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls [label] into view and taps it.
  Future<void> tapButton(WidgetTester tester, String label) async {
    final Finder target = find.text(label);
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tapButton(tester, 'Edit Nutrition');
    expect(find.byType(EditNutritionScreen), findsOneWidget);
  }

  testWidgets('1. the result screen shows the AI estimate', (
    WidgetTester tester,
  ) async {
    await pumpResultScreen(tester);

    expect(find.text('Grilled chicken salad'), findsOneWidget);
    expect(find.text('580'), findsOneWidget);
    expect(find.text('~320 g'), findsWidgets);
    expect(find.text('High confidence'), findsOneWidget);
    expect(
      find.text('Dressing assumed to be olive oil based.'),
      findsOneWidget,
    );
    expect(
      find.text('Nutrition values are AI estimates and may not be exact.'),
      findsOneWidget,
    );
    // Nothing is edited yet.
    expect(find.text('Edited'), findsNothing);
  });

  testWidgets('2. Edit Nutrition opens the editor with the current values', (
    WidgetTester tester,
  ) async {
    await pumpResultScreen(tester);
    await openEditor(tester);

    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Grilled chicken salad'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, '580'), findsOneWidget);
  });

  testWidgets('3. an empty food name is rejected', (WidgetTester tester) async {
    await pumpResultScreen(tester);
    await openEditor(tester);

    await tester.enterText(find.byType(TextFormField).at(_nameField), '');
    await tapButton(tester, 'Save Changes');

    expect(find.text('Enter a food name'), findsOneWidget);
    // The editor stays open, so nothing was saved.
    expect(find.byType(EditNutritionScreen), findsOneWidget);
  });

  testWidgets('4. calories that are not a number are rejected', (
    WidgetTester tester,
  ) async {
    await pumpResultScreen(tester);
    await openEditor(tester);

    await tester.enterText(
      find.byType(TextFormField).at(_caloriesField),
      '1.2.3',
    );
    await tapButton(tester, 'Save Changes');

    expect(find.text('Enter calories as a number'), findsOneWidget);
    expect(find.byType(EditNutritionScreen), findsOneWidget);

    // An empty value is rejected too.
    await tester.enterText(find.byType(TextFormField).at(_caloriesField), '');
    await tapButton(tester, 'Save Changes');
    expect(find.text('Enter the calories'), findsOneWidget);
  });

  testWidgets('5. a portion of zero is rejected', (WidgetTester tester) async {
    await pumpResultScreen(tester);
    await openEditor(tester);

    await tester.enterText(find.byType(TextFormField).at(_portionField), '0');
    await tapButton(tester, 'Save Changes');

    expect(find.text('Portion must be greater than 0'), findsOneWidget);
    expect(find.byType(EditNutritionScreen), findsOneWidget);
  });

  testWidgets('6. Cancel discards the changes', (WidgetTester tester) async {
    await pumpResultScreen(tester);
    await openEditor(tester);

    await tester.enterText(
      find.byType(TextFormField).at(_caloriesField),
      '620',
    );
    await tapButton(tester, 'Cancel');

    expect(find.byType(EditNutritionScreen), findsNothing);
    expect(find.text('580'), findsOneWidget);
    expect(find.text('620'), findsNothing);
    expect(find.text('Edited'), findsNothing);
  });

  testWidgets('7. Save Changes updates the displayed result', (
    WidgetTester tester,
  ) async {
    await pumpResultScreen(tester);
    await openEditor(tester);

    await tester.enterText(
      find.byType(TextFormField).at(_caloriesField),
      '620',
    );
    await tester.enterText(
      find.byType(TextFormField).at(_nameField),
      'Chicken salad, large',
    );
    await tapButton(tester, 'Save Changes');

    expect(find.byType(EditNutritionScreen), findsNothing);
    expect(find.text('620'), findsOneWidget);
    expect(find.text('Chicken salad, large'), findsOneWidget);
    expect(find.text('Edited'), findsOneWidget);
    // The original estimate is still on show.
    expect(find.text('AI estimated 580 kcal'), findsOneWidget);
  });

  testWidgets('8. editing leaves the AI confidence untouched', (
    WidgetTester tester,
  ) async {
    await pumpResultScreen(tester);
    await openEditor(tester);

    await tester.enterText(
      find.byType(TextFormField).at(_caloriesField),
      '620',
    );
    await tapButton(tester, 'Save Changes');

    expect(find.text('High confidence'), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
  });

  testWidgets('9. editing leaves the AI assumptions untouched', (
    WidgetTester tester,
  ) async {
    await pumpResultScreen(tester);
    await openEditor(tester);

    await tester.enterText(
      find.byType(TextFormField).at(_caloriesField),
      '620',
    );
    await tapButton(tester, 'Save Changes');

    expect(
      find.text('Dressing assumed to be olive oil based.'),
      findsOneWidget,
    );
    expect(find.text('Assumptions'), findsOneWidget);
  });

  testWidgets('10. Save Meal stores the meal and confirms it', (
    WidgetTester tester,
  ) async {
    await pumpResultScreen(tester);

    expect(appState.pendingMeal, isNull);
    expect(mealRepository.meals, isEmpty);

    await tapButton(tester, 'Save Meal');

    expect(find.text('Meal saved'), findsWidgets);
    expect(mealRepository.saveCalls, 1);
    expect(mealRepository.allocatedMealIds, hasLength(1));
    expect(mealRepository.submittedMealIds, <String?>[
      mealRepository.allocatedMealIds.single,
    ]);
    expect(mealRepository.meals, hasLength(1));
    expect(mealRepository.meals.single.current.calories, 580);

    // The staging area is cleared only after the write succeeds.
    expect(appState.pendingMeal, isNull);
  });

  testWidgets('an ambiguous commit retries the same document id', (
    WidgetTester tester,
  ) async {
    final FakeMealRepository repository = FakeMealRepository()
      ..saveFailureAfterCommit = const MealRepositoryFailure(
        'The save result could not be confirmed. Please try again.',
      );
    await pumpResultScreen(tester, repository: repository);

    await tapButton(tester, 'Save Meal');

    expect(find.text('Meal not saved'), findsOneWidget);
    expect(repository.meals, hasLength(1));
    final String allocatedId = repository.allocatedMealIds.single;
    expect(repository.meals.single.id, allocatedId);

    repository.saveFailureAfterCommit = null;
    await tapButton(tester, 'Try Again');

    expect(repository.allocatedMealIds, <String>[allocatedId]);
    expect(repository.submittedMealIds, <String?>[allocatedId, allocatedId]);
    expect(repository.meals, hasLength(1));
    expect(repository.meals.single.id, allocatedId);
  });

  testWidgets('repeated retries never allocate additional ids', (
    WidgetTester tester,
  ) async {
    final FakeMealRepository repository = FakeMealRepository()
      ..saveFailureAfterCommit = const MealRepositoryFailure(
        'The save result could not be confirmed. Please try again.',
      );
    await pumpResultScreen(tester, repository: repository);

    await tapButton(tester, 'Save Meal');
    await tapButton(tester, 'Try Again');

    final String allocatedId = repository.allocatedMealIds.single;
    expect(repository.submittedMealIds, <String?>[allocatedId, allocatedId]);
    expect(repository.meals, hasLength(1));

    repository.saveFailureAfterCommit = null;
    await tapButton(tester, 'Try Again');

    expect(repository.allocatedMealIds, <String>[allocatedId]);
    expect(repository.submittedMealIds, <String?>[
      allocatedId,
      allocatedId,
      allocatedId,
    ]);
    expect(repository.meals, hasLength(1));
  });

  testWidgets('editing before an ambiguous retry keeps the same id', (
    WidgetTester tester,
  ) async {
    final FakeMealRepository repository = FakeMealRepository()
      ..saveFailureAfterCommit = const MealRepositoryFailure(
        'The save result could not be confirmed. Please try again.',
      );
    await pumpResultScreen(tester, repository: repository);

    await tapButton(tester, 'Save Meal');
    final String allocatedId = repository.allocatedMealIds.single;
    await openEditor(tester);
    await tester.enterText(
      find.byType(TextFormField).at(_caloriesField),
      '620',
    );
    await tapButton(tester, 'Save Changes');

    repository.saveFailureAfterCommit = null;
    await tapButton(tester, 'Save Meal');

    expect(repository.allocatedMealIds, <String>[allocatedId]);
    expect(repository.submittedMealIds, <String?>[allocatedId, allocatedId]);
    expect(repository.meals, hasLength(1));
    expect(repository.meals.single.id, allocatedId);
    expect(repository.meals.single.current.calories, 620);
  });

  testWidgets('a genuinely new result flow allocates a different id', (
    WidgetTester tester,
  ) async {
    final FakeMealRepository repository = FakeMealRepository();
    await pumpResultScreen(tester, repository: repository);
    await tapButton(tester, 'Save Meal');
    final String firstId = repository.allocatedMealIds.single;

    await pumpResultScreen(tester, repository: repository);
    await tapButton(tester, 'Save Meal');

    expect(repository.allocatedMealIds, hasLength(2));
    expect(repository.allocatedMealIds.last, isNot(firstId));
    expect(repository.meals, hasLength(2));
  });

  testWidgets('a failed save keeps the meal so it can be retried', (
    WidgetTester tester,
  ) async {
    final FakeMealRepository repository = FakeMealRepository()
      ..saveFailure = const MealRepositoryFailure(
        'No connection to the meal database. Please try again.',
      );
    await pumpResultScreen(tester, repository: repository);

    await tapButton(tester, 'Save Meal');

    expect(find.text('Meal not saved'), findsOneWidget);
    expect(
      find.text('No connection to the meal database. Please try again.'),
      findsOneWidget,
    );
    // The meal is still staged, and the button offers another go.
    expect(appState.pendingMeal, isNotNull);
    expect(find.text('Try Again'), findsOneWidget);

    // Retrying after the problem clears saves the same meal once.
    repository.saveFailure = null;
    await tapButton(tester, 'Try Again');

    expect(find.text('Meal saved'), findsWidgets);
    expect(repository.meals, hasLength(1));
    expect(appState.pendingMeal, isNull);
  });

  testWidgets('tapping Save twice does not store the meal twice', (
    WidgetTester tester,
  ) async {
    await pumpResultScreen(tester);

    await tapButton(tester, 'Save Meal');
    // The button becomes Done, so a second tap cannot start another write.
    expect(find.text('Save Meal'), findsNothing);
    expect(find.text('Done'), findsOneWidget);

    expect(mealRepository.saveCalls, 1);
    expect(mealRepository.meals, hasLength(1));
  });

  testWidgets('editing after saving updates the same meal', (
    WidgetTester tester,
  ) async {
    await pumpResultScreen(tester);
    await tapButton(tester, 'Save Meal');
    final String savedId = mealRepository.meals.single.id;

    await openEditor(tester);
    await tester.enterText(
      find.byType(TextFormField).at(_caloriesField),
      '620',
    );
    await tapButton(tester, 'Save Changes');
    await tapButton(tester, 'Save Meal');

    // Still one meal, now carrying the edit and the original estimate.
    expect(mealRepository.meals, hasLength(1));
    final SavedMeal stored = mealRepository.meals.single;
    expect(stored.id, savedId);
    expect(stored.current.calories, 620);
    expect(stored.aiEstimate.calories, 580);
    expect(stored.current.confidence, stored.aiEstimate.confidence);
    expect(stored.isEdited, isTrue);
  });
}
