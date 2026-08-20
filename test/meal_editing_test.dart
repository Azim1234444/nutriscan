// Tests for Phase 2K: correcting and removing a meal that is already saved.
//
// Two layers are covered. The screen tests drive History and the editor with
// an in-memory repository, so they check what the app asks to be written. The
// document tests run the real repository against an in-memory Firestore, so
// they check what actually lands in `users/{uid}/meals/{mealId}` - which is
// where the promises about ids, creation times and the AI estimate have to
// hold.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/main_shell.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/food_analysis_result.dart';
import 'package:nutriscan/models/food_entry.dart';
import 'package:nutriscan/models/reviewed_meal.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/screens/history/edit_meal_screen.dart';
import 'package:nutriscan/screens/history/history_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/meal_repository.dart';
import 'package:nutriscan/theme/app_theme.dart';

import 'support/test_doubles.dart';

/// Field order on the meal editor, top to bottom.
const int _nameField = 0;
const int _descriptionField = 1;
const int _portionField = 2;
const int _caloriesField = 3;
const int _proteinField = 4;
const int _carbsField = 5;
const int _fatField = 6;
const int _fiberField = 7;

void main() {
  late AppState appState;
  late FakeAuthService auth;

  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day, 12);
  final DateTime yesterday = today.subtract(const Duration(days: 1));

  setUp(() {
    appState = AppState();
    auth = FakeAuthService();
  });

  tearDown(() => appState.dispose());

  /// A saved meal whose numbers the user has already changed.
  SavedMeal editedMeal({
    required String id,
    required DateTime createdAt,
    double aiCalories = 580,
    double currentCalories = 620,
    String foodName = 'Chicken salad, large',
  }) {
    return SavedMeal(
      id: id,
      userId: 'user-a',
      mealType: MealType.lunch,
      aiEstimate: buildAnalysis(calories: aiCalories),
      current: buildAnalysis(calories: currentCalories, foodName: foodName),
      isEdited: true,
      createdAt: createdAt,
    );
  }

  Future<void> pumpWidgetTree(
    WidgetTester tester,
    Widget home,
    FakeMealRepository repository,
  ) async {
    addTearDown(repository.dispose);
    await tester.binding.setSurfaceSize(const Size(500, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ServicesScope(
        authService: auth,
        mealRepository: repository,
        profileRepository: FakeProfileRepository(),
        child: AppScope(
          state: appState,
          child: MaterialApp(
            theme: AppTheme.light,
            onGenerateRoute: AppRoutes.onGenerateRoute,
            home: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpHistory(WidgetTester tester, FakeMealRepository repository) {
    return pumpWidgetTree(tester, const HistoryScreen(), repository);
  }

  /// Opens the overflow menu on the only meal in the list.
  Future<void> openMealMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Meal actions').first);
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await openMealMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseDelete(WidgetTester tester) async {
    await openMealMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, int field, String value) async {
    await tester.enterText(find.byType(TextFormField).at(field), value);
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
  }

  group('History actions', () {
    testWidgets('1. a saved meal is listed with an action menu', (
      WidgetTester tester,
    ) async {
      await pumpHistory(
        tester,
        FakeMealRepository(
          meals: <SavedMeal>[
            buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken'),
          ],
        ),
      );

      expect(find.text('Chicken'), findsOneWidget);
      expect(find.byTooltip('Meal actions'), findsOneWidget);
    });

    testWidgets('2. the menu offers Edit and Delete', (
      WidgetTester tester,
    ) async {
      await pumpHistory(
        tester,
        FakeMealRepository(
          meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
        ),
      );

      await openMealMenu(tester);

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('3. every meal gets its own menu', (WidgetTester tester) async {
      await pumpHistory(
        tester,
        FakeMealRepository(
          meals: <SavedMeal>[
            buildSavedMeal(id: 'a', createdAt: today, foodName: 'Lunch'),
            buildSavedMeal(
              id: 'b',
              createdAt: today.subtract(const Duration(hours: 4)),
              foodName: 'Breakfast',
            ),
            buildSavedMeal(id: 'c', createdAt: yesterday, foodName: 'Dinner'),
          ],
        ),
      );

      // Both of today's meals, each with its own menu.
      expect(find.byTooltip('Meal actions'), findsNWidgets(2));
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget);

      // Yesterday's meal is on yesterday, with a menu of its own.
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();

      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.byTooltip('Meal actions'), findsOneWidget);
    });

    testWidgets('4. an edited meal is marked, with the AI figure alongside', (
      WidgetTester tester,
    ) async {
      await pumpHistory(
        tester,
        FakeMealRepository(
          meals: <SavedMeal>[editedMeal(id: 'a', createdAt: today)],
        ),
      );

      expect(find.text('Edited'), findsOneWidget);
      // The user's number is the one shown; the model's is still readable.
      expect(find.text('620'), findsWidgets);
      expect(find.text('AI 580'), findsOneWidget);
    });

    testWidgets('5. an untouched meal is not marked as edited', (
      WidgetTester tester,
    ) async {
      await pumpHistory(
        tester,
        FakeMealRepository(
          meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
        ),
      );

      expect(find.text('Edited'), findsNothing);
      expect(find.textContaining('AI '), findsNothing);
    });
  });

  group('Editing', () {
    testWidgets('6. Edit opens that meal, prefilled', (
      WidgetTester tester,
    ) async {
      await pumpHistory(
        tester,
        FakeMealRepository(
          meals: <SavedMeal>[
            buildSavedMeal(
              id: 'a',
              createdAt: today,
              foodName: 'Chicken salad',
              calories: 580,
            ),
            buildSavedMeal(
              id: 'b',
              createdAt: today.subtract(const Duration(hours: 5)),
              foodName: 'Porridge',
            ),
          ],
        ),
      );

      // Both are on the day being shown; the first card is the newest meal,
      // so that is the one opened.
      expect(find.text('Porridge'), findsOneWidget);
      await openEditor(tester);

      expect(find.byType(EditMealScreen), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Chicken salad'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, '580'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '320'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '42'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '18'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '24'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '6'), findsOneWidget);
      // Nothing from the other meal.
      expect(find.widgetWithText(TextFormField, 'Porridge'), findsNothing);
    });

    testWidgets('7. an empty food name is rejected', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      await enter(tester, _nameField, '');
      await tapSave(tester);

      expect(find.text('Enter a food name'), findsOneWidget);
      expect(find.byType(EditMealScreen), findsOneWidget);
      expect(repository.updateCalls, 0);
    });

    testWidgets('8. a portion of zero is rejected', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      await enter(tester, _portionField, '0');
      await tapSave(tester);

      expect(find.text('Portion must be greater than 0'), findsOneWidget);
      expect(repository.updateCalls, 0);
    });

    testWidgets('9. calories must be a number, and must be there', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      await enter(tester, _caloriesField, '1.2.3');
      await tapSave(tester);
      expect(find.text('Enter calories as a number'), findsOneWidget);

      await enter(tester, _caloriesField, '');
      await tapSave(tester);
      expect(find.text('Enter the calories'), findsOneWidget);

      expect(repository.updateCalls, 0);
    });

    testWidgets('10. every macro field is validated the same way', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      for (final (int field, String label) in <(int, String)>[
        (_proteinField, 'protein'),
        (_carbsField, 'carbohydrates'),
        (_fatField, 'fat'),
        (_fiberField, 'fibre'),
      ]) {
        await enter(tester, field, '');
        await tapSave(tester);
        expect(
          find.text('Enter the $label'),
          findsOneWidget,
          reason: 'an empty $label should be rejected',
        );

        await enter(tester, field, '1.2.3');
        await tapSave(tester);
        expect(
          find.text('Enter $label as a number'),
          findsOneWidget,
          reason: '$label must be a number',
        );

        // Put it back so the next field is tested on its own.
        await enter(tester, field, '5');
      }

      expect(repository.updateCalls, 0);
      expect(find.byType(EditMealScreen), findsOneWidget);
    });

    testWidgets('11. Save writes the corrected values to the same meal', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      await enter(tester, _nameField, 'Chicken salad, large');
      await enter(tester, _portionField, '400');
      await enter(tester, _caloriesField, '620');
      await enter(tester, _proteinField, '50');
      await tapSave(tester);

      expect(repository.updateCalls, 1);
      final SavedMeal written = repository.updatedMeals.single;
      expect(written.id, 'a');
      expect(written.current.foodName, 'Chicken salad, large');
      expect(written.current.portionGrams, 400);
      expect(written.current.calories, 620);
      expect(written.current.proteinG, 50);
      // Untouched fields keep their values.
      expect(written.current.carbsG, 18);
      expect(written.current.fatG, 24);
      expect(written.current.fiberG, 6);
    });

    testWidgets('12. the meal type can be corrected', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      // The meal was saved as lunch, from the clock.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Dinner'));
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(repository.updatedMeals.single.mealType, MealType.dinner);
      expect(repository.meals.single.mealType, MealType.dinner);
    });

    testWidgets('13. the description can be corrected', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      await enter(tester, _descriptionField, 'Half the dressing.');
      await tapSave(tester);

      expect(
        repository.updatedMeals.single.current.description,
        'Half the dressing.',
      );
    });

    testWidgets('14. Cancel changes nothing', (WidgetTester tester) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      await enter(tester, _caloriesField, '999');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(EditMealScreen), findsNothing);
      expect(repository.updateCalls, 0);
      expect(repository.meals.single.current.calories, 580);
      expect(find.text('580'), findsWidgets);
      expect(find.text('999'), findsNothing);
    });

    testWidgets('15. the AI estimate is left exactly as it was', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      await enter(tester, _nameField, 'Something else entirely');
      await enter(tester, _caloriesField, '900');
      await enter(tester, _proteinField, '90');
      await tapSave(tester);

      final FoodAnalysisResult ai = repository.updatedMeals.single.aiEstimate;
      expect(ai.foodName, 'Chicken salad');
      expect(ai.calories, 580);
      expect(ai.proteinG, 42);
      expect(ai.portionGrams, 320);
      // The model's own working is untouched too.
      expect(ai.confidence, 0.85);
      expect(ai.assumptions, <String>[
        'Dressing assumed to be olive oil based.',
      ]);
      expect(ai.items.single.name, 'Grilled chicken breast');
      expect(ai.items.single.portionGrams, 150);

      // And the same after the write was applied.
      expect(repository.meals.single.aiEstimate.calories, 580);
    });

    testWidgets('16. isEdited becomes true once the values differ', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      await enter(tester, _caloriesField, '620');
      await tapSave(tester);

      expect(repository.updatedMeals.single.isEdited, isTrue);
      expect(repository.meals.single.isEdited, isTrue);
      expect(find.text('Edited'), findsOneWidget);
    });

    testWidgets('17. isEdited clears again when the AI values are restored', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[editedMeal(id: 'a', createdAt: today)],
      );
      await pumpHistory(tester, repository);
      expect(find.text('Edited'), findsOneWidget);

      await openEditor(tester);
      // Back to exactly what the model said.
      await enter(tester, _nameField, 'Grilled chicken salad');
      await enter(tester, _caloriesField, '580');
      await tapSave(tester);

      expect(repository.updatedMeals.single.isEdited, isFalse);
      expect(repository.meals.single.isEdited, isFalse);
      expect(find.text('Edited'), findsNothing);
    });

    testWidgets('18. the corrected values show in History', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      await enter(tester, _nameField, 'Chicken salad, large');
      await enter(tester, _caloriesField, '620');
      await tapSave(tester);

      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text('Chicken salad, large'), findsOneWidget);
      expect(find.text('620'), findsWidgets);
      // The AI figure is still there, and still labelled as the AI's.
      expect(find.text('AI 580'), findsOneWidget);
    });

    testWidgets('19. the meal keeps its day after an edit', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: yesterday, foodName: 'Porridge'),
        ],
      );
      await pumpHistory(tester, repository);

      // Yesterday's meal is edited from yesterday.
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(find.text('Porridge'), findsOneWidget);

      await openEditor(tester);
      await enter(tester, _caloriesField, '300');
      await tapSave(tester);

      expect(repository.meals.single.createdAt, yesterday);
      // Still on yesterday, and still there: the edit did not move it. The
      // bare text 'Today' is now the return-to-today button, so the meal not
      // being under today is checked by going there.
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Porridge'), findsOneWidget);
      expect(find.text('300'), findsWidgets);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Porridge'), findsNothing);
    });
  });

  group('Dashboard', () {
    /// Switches to a tab by its bottom-bar icon.
    Future<void> openTab(WidgetTester tester, IconData icon) async {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
    }

    testWidgets('20. today\'s totals follow an edit', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(
            id: 'a',
            createdAt: today,
            calories: 400,
            proteinG: 30,
            carbsG: 20,
            fatG: 10,
          ),
        ],
      );
      await pumpWidgetTree(tester, const MainShell(), repository);
      expect(find.text('400 kcal'), findsOneWidget);

      await openTab(tester, Icons.history_outlined);
      await openEditor(tester);
      await enter(tester, _caloriesField, '500');
      await enter(tester, _proteinField, '35');
      await tapSave(tester);
      await openTab(tester, Icons.home_outlined);

      expect(find.text('500 kcal'), findsOneWidget);
      expect(find.text('400 kcal'), findsNothing);
      expect(find.text('35 g'), findsOneWidget);
    });

    testWidgets('21. today\'s totals drop when a meal is deleted', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, calories: 400),
          buildSavedMeal(
            id: 'b',
            createdAt: today.subtract(const Duration(hours: 1)),
            calories: 220,
            foodName: 'Toast',
          ),
        ],
      );
      await pumpWidgetTree(tester, const MainShell(), repository);
      expect(find.text('620 kcal'), findsOneWidget);

      await openTab(tester, Icons.history_outlined);
      await chooseDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await openTab(tester, Icons.home_outlined);

      expect(find.text('220 kcal'), findsOneWidget);
      expect(find.text('620 kcal'), findsNothing);
      // The deleted meal has gone from the recent list as well.
      expect(find.text('Grilled chicken salad'), findsNothing);
      expect(find.text('Toast'), findsWidgets);
    });
  });

  group('Deleting', () {
    testWidgets('22. Delete asks first', (WidgetTester tester) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      await pumpHistory(tester, repository);

      await chooseDelete(tester);

      expect(find.text('Delete this meal?'), findsOneWidget);
      expect(
        find.textContaining('This action cannot be undone.'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      // Nothing has been asked of the repository yet.
      expect(repository.deleteCalls, 0);
    });

    testWidgets('23. Cancel keeps the meal', (WidgetTester tester) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      await pumpHistory(tester, repository);

      await chooseDelete(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, 0);
      expect(repository.deletedIds, isEmpty);
      expect(find.text('Chicken salad'), findsOneWidget);
    });

    testWidgets('24. confirming removes the meal from the list', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      await pumpHistory(tester, repository);

      await chooseDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, <String>['a']);
      expect(find.text('Chicken salad'), findsNothing);
      expect(find.text('No meals saved yet.'), findsOneWidget);
    });

    testWidgets('25. only the chosen meal goes', (WidgetTester tester) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Lunch'),
          buildSavedMeal(
            id: 'b',
            createdAt: today.subtract(const Duration(hours: 4)),
            foodName: 'Dinner',
          ),
        ],
      );
      await pumpHistory(tester, repository);

      await tester.tap(find.byTooltip('Meal actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, <String>['a']);
      expect(find.text('Lunch'), findsNothing);
      expect(find.text('Dinner'), findsOneWidget);
    });

    testWidgets('26. a swipe still works, and still asks first', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      await pumpHistory(tester, repository);

      await tester.drag(find.text('Chicken salad'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Delete this meal?'), findsOneWidget);

      // Backing out of the dialog deletes nothing and keeps the card.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.deleteCalls, 0);
      expect(find.text('Chicken salad'), findsOneWidget);

      await tester.drag(find.text('Chicken salad'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, <String>['a']);
      expect(find.text('No meals saved yet.'), findsOneWidget);
    });
  });

  group('When a write fails', () {
    testWidgets('27. a failed delete keeps the meal and says why', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      repository.deleteFailure = const MealRepositoryFailure(
        'No connection to the meal database. Please try again.',
      );
      await pumpHistory(tester, repository);

      await chooseDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(
        find.text('No connection to the meal database. Please try again.'),
        findsOneWidget,
      );
      // The meal is still there, because it was never removed.
      expect(find.text('Chicken salad'), findsOneWidget);
      expect(find.text('No meals saved yet.'), findsNothing);
      expect(repository.deletedIds, isEmpty);
      expect(repository.meals, hasLength(1));
    });

    testWidgets('28. a failed swipe delete leaves the card in place', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      repository.deleteFailure = const MealRepositoryFailure(
        'The meal could not be deleted. Please try again.',
      );
      await pumpHistory(tester, repository);

      await tester.drag(find.text('Chicken salad'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Chicken salad'), findsOneWidget);
      expect(repository.meals, hasLength(1));
    });

    testWidgets('29. a retry after a failed delete works', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      repository.deleteFailure = const MealRepositoryFailure(
        'The meal could not be deleted. Please try again.',
      );
      await pumpHistory(tester, repository);

      await chooseDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Chicken salad'), findsOneWidget);

      repository.deleteFailure = null;
      await chooseDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, <String>['a']);
      expect(find.text('No meals saved yet.'), findsOneWidget);
    });

    testWidgets('30. a failed edit keeps the form and the stored values', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      repository.updateFailure = const MealRepositoryFailure(
        'No connection to the meal database. Please try again.',
      );
      await pumpHistory(tester, repository);
      await openEditor(tester);

      await enter(tester, _caloriesField, '620');
      await tapSave(tester);

      // Still on the form, with the typed values kept for a retry.
      expect(find.byType(EditMealScreen), findsOneWidget);
      expect(find.text('Changes not saved'), findsOneWidget);
      expect(
        find.text('No connection to the meal database. Please try again.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, '620'), findsOneWidget);
      // Nothing was written.
      expect(repository.meals.single.current.calories, 580);

      // And a retry gets through.
      repository.updateFailure = null;
      await tapSave(tester);
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(repository.meals.single.current.calories, 620);
    });

    testWidgets('31. a second delete cannot start while one is running', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      final Completer<void> gate = Completer<void>();
      repository.writeGate = gate;
      await pumpHistory(tester, repository);

      await chooseDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(repository.deleteCalls, 1);

      // The menu is closed while the delete runs, so there is no second way in.
      await tester.tap(find.byTooltip('Meal actions'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);

      // Nor does swiping start another one.
      await tester.drag(find.text('Chicken salad'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Delete this meal?'), findsNothing);
      expect(repository.deleteCalls, 1);

      gate.complete();
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, 1);
      expect(repository.deletedIds, <String>['a']);
    });

    testWidgets('32. a second save cannot start while one is running', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );
      final Completer<void> gate = Completer<void>();
      repository.writeGate = gate;
      await pumpHistory(tester, repository);
      await openEditor(tester);

      await enter(tester, _caloriesField, '620');
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      expect(repository.updateCalls, 1);

      // The button is disabled, so further taps do nothing at all.
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(repository.updateCalls, 1);

      gate.complete();
      await tester.pumpAndSettle();

      expect(repository.updateCalls, 1);
      expect(repository.meals.single.current.calories, 620);
    });
  });

  group('the stored document', () {
    late FakeFirebaseFirestore firestore;
    late FakeAuthService documentAuth;
    late FirestoreMealRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      documentAuth = FakeAuthService(userId: 'user-a');
      repository = FirestoreMealRepository(
        authService: documentAuth,
        firestore: firestore,
      );
    });

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> documentsFor(
      String userId,
    ) async {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('meals')
          .get();
      return snapshot.docs;
    }

    /// Saves a meal and hands back the stored form of it.
    Future<SavedMeal> saveMeal({double calories = 580}) async {
      final String id = await repository.saveMeal(
        ReviewedMeal.fromAnalysis(buildAnalysis(calories: calories)),
      );
      final List<SavedMeal> meals = await repository.watchMeals().first;
      return meals.firstWhere((SavedMeal meal) => meal.id == id);
    }

    test('33. an edit updates the same document, and adds no other', () async {
      final SavedMeal saved = await saveMeal();

      await repository.updateMeal(
        saved.withEdits(saved.current.copyWith(calories: 620)),
      );

      final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
          await documentsFor('user-a');
      expect(docs, hasLength(1));
      expect(docs.single.id, saved.id);
    });

    test('34. the creation time is left alone', () async {
      final SavedMeal saved = await saveMeal();
      final Object? createdBefore = (await documentsFor('user-a')).single
          .data()[MealFields.createdAt];

      await repository.updateMeal(
        saved.withEdits(saved.current.copyWith(calories: 620)),
      );

      final Map<String, dynamic> after = (await documentsFor('user-a')).single
          .data();
      expect(after[MealFields.createdAt], createdBefore);
      expect(
        (await repository.watchMeals().first).single.createdAt,
        saved.createdAt,
      );
    });

    test('35. updatedAt is stamped by the server on every edit', () async {
      final SavedMeal saved = await saveMeal();
      final Timestamp createdAt =
          (await documentsFor('user-a')).single.data()[MealFields.createdAt]
              as Timestamp;

      await repository.updateMeal(
        saved.withEdits(saved.current.copyWith(calories: 620)),
      );

      final Object? updatedAt = (await documentsFor('user-a')).single
          .data()[MealFields.updatedAt];
      expect(updatedAt, isA<Timestamp>());
      expect(
        (updatedAt! as Timestamp).compareTo(createdAt),
        greaterThanOrEqualTo(0),
      );
      // It comes back on the model too.
      expect((await repository.watchMeals().first).single.updatedAt, isNotNull);
    });

    test('36. the AI estimate is not part of an edit at all', () async {
      final SavedMeal saved = await saveMeal();
      final Map<String, dynamic> before = (await documentsFor('user-a')).single
          .data();

      await repository.updateMeal(
        saved.withEdits(
          saved.current.copyWith(calories: 900, foodName: 'Something else'),
        ),
      );

      final Map<String, dynamic> after = (await documentsFor('user-a')).single
          .data();
      expect(after[MealFields.aiEstimate], before[MealFields.aiEstimate]);

      final Map<String, dynamic> ai = Map<String, dynamic>.from(
        after[MealFields.aiEstimate] as Map,
      );
      expect(ai[MealFields.foodName], 'Grilled chicken salad');
      expect(ai[MealFields.calories], 580);
      expect(ai[MealFields.confidence], 0.85);
      expect(ai[MealFields.assumptions], <String>[
        'Dressing assumed to be olive oil based.',
      ]);
      expect(ai[MealFields.items], hasLength(1));

      // The user's values did change.
      final Map<String, dynamic> current = Map<String, dynamic>.from(
        after[MealFields.current] as Map,
      );
      expect(current[MealFields.calories], 900);
      expect(after[MealFields.isEdited], isTrue);
    });

    test(
      '37. an edit never writes the owner, so it cannot be changed',
      () async {
        final SavedMeal saved = await saveMeal();

        final Map<String, Object?> body = mealEditToDocument(
          saved.withEdits(saved.current.copyWith(calories: 620)),
          updatedAt: DateTime.now(),
        );

        expect(body.containsKey(MealFields.userId), isFalse);
        expect(body.containsKey(MealFields.aiEstimate), isFalse);
        expect(body.containsKey(MealFields.createdAt), isFalse);
        expect(body.containsKey('imageBase64'), isFalse);
        expect(body.containsKey('image'), isFalse);

        await repository.updateMeal(
          saved.withEdits(saved.current.copyWith(calories: 620)),
        );
        expect(
          (await documentsFor('user-a')).single.data()[MealFields.userId],
          'user-a',
        );
      },
    );

    test('38. a meal belonging to somebody else is refused', () async {
      final SavedMeal saved = await saveMeal();
      final SavedMeal theirs = SavedMeal(
        id: saved.id,
        userId: 'user-b',
        mealType: saved.mealType,
        aiEstimate: saved.aiEstimate,
        current: saved.current.copyWith(calories: 1),
        isEdited: true,
        createdAt: saved.createdAt,
      );

      await expectLater(
        repository.updateMeal(theirs),
        throwsA(
          isA<MealRepositoryFailure>().having(
            (MealRepositoryFailure error) => error.message,
            'message',
            'That meal belongs to a different account.',
          ),
        ),
      );

      // Nothing was written.
      expect(
        (await repository.watchMeals().first).single.current.calories,
        580,
      );
    });

    test('39. one user\'s edit cannot reach another user\'s meal', () async {
      // A meal owned by somebody else, written straight to the database.
      await firestore
          .collection('users')
          .doc('user-b')
          .collection('meals')
          .doc('their-meal')
          .set(<String, Object?>{
            MealFields.userId: 'user-b',
            MealFields.foodName: 'Their pasta',
            MealFields.isEdited: false,
            MealFields.createdAt: DateTime.now(),
            MealFields.current: <String, Object?>{
              MealFields.foodName: 'Their pasta',
              MealFields.calories: 700,
            },
            MealFields.aiEstimate: <String, Object?>{
              MealFields.foodName: 'Their pasta',
              MealFields.calories: 700,
            },
          });

      final SavedMeal saved = await saveMeal();
      // Same document id as theirs would be, but signed in as user-a: the
      // write can only land under user-a's own path.
      await repository.updateMeal(
        saved.withEdits(saved.current.copyWith(calories: 620)),
      );

      final Map<String, dynamic> theirs = (await documentsFor('user-b')).single
          .data();
      expect(theirs[MealFields.userId], 'user-b');
      expect(
        Map<String, dynamic>.from(
          theirs[MealFields.current] as Map,
        )[MealFields.calories],
        700,
      );
      expect(theirs.containsKey(MealFields.updatedAt), isFalse);
    });

    test('40. a meal that has already gone is not recreated', () async {
      final SavedMeal saved = await saveMeal();
      await repository.deleteMeal(saved.id);

      await expectLater(
        repository.updateMeal(
          saved.withEdits(saved.current.copyWith(calories: 620)),
        ),
        throwsA(isA<MealRepositoryFailure>()),
      );

      expect(await documentsFor('user-a'), isEmpty);
    });

    test('41. an edit that restores the AI values clears isEdited', () async {
      final SavedMeal saved = await saveMeal();

      await repository.updateMeal(
        saved.withEdits(saved.current.copyWith(calories: 620)),
      );
      expect(
        (await documentsFor('user-a')).single.data()[MealFields.isEdited],
        isTrue,
      );

      final SavedMeal edited = (await repository.watchMeals().first).single;
      await repository.updateMeal(
        edited.withEdits(edited.current.copyWith(calories: 580)),
      );

      expect(
        (await documentsFor('user-a')).single.data()[MealFields.isEdited],
        isFalse,
      );
    });
  });

  // Phase 2S-3, H2. The success path popped the navigator without checking
  // the screen was still there. Nothing blocks the system back gesture while
  // a write runs, so leaving mid-save meant the delayed pop landed on
  // whatever route was on top by then - the tabbed shell underneath.
  group('leaving the editor while the save is still running', () {
    testWidgets('42. the shell is not popped when the save lands late', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      final Completer<void> gate = Completer<void>();
      repository.writeGate = gate;

      await pumpWidgetTree(tester, const MainShell(), repository);
      await tester.tap(find.byIcon(Icons.history_outlined));
      await tester.pumpAndSettle();
      await openEditor(tester);
      expect(find.byType(EditMealScreen), findsOneWidget);

      // The write starts and is held open.
      await enter(tester, _caloriesField, '620');
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      expect(repository.updateCalls, 1);

      // The user backs out before it returns, exactly as the hardware back
      // button does: the editor goes, the shell is uncovered.
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator),
      );
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(EditMealScreen), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);

      // Now the write lands, with nothing left to report to.
      gate.complete();
      await tester.pumpAndSettle();

      // The shell survived: this is the whole point of the test.
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.byType(HistoryScreen), findsOneWidget);
      // And the write itself happened exactly once and was stored.
      expect(repository.updateCalls, 1);
      expect(repository.meals.single.current.calories, 620);
    });

    testWidgets('43. a save the user waits for still returns to History', (
      WidgetTester tester,
    ) async {
      // The unchanged half of the contract: when the editor is still there,
      // the success path pops with true and reports it as it always did.
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      final Completer<void> gate = Completer<void>();
      repository.writeGate = gate;

      await pumpWidgetTree(tester, const MainShell(), repository);
      await tester.tap(find.byIcon(Icons.history_outlined));
      await tester.pumpAndSettle();
      await openEditor(tester);

      await enter(tester, _caloriesField, '640');
      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(EditMealScreen), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.text('Meal updated'), findsOneWidget);
      expect(repository.meals.single.current.calories, 640);
    });
  });
}
