// Tests for Phase 2L: History one day at a time.
//
// The screen reads a single day through `MealRepository.mealsForDate`, so
// these drive the date control and check what is asked for, what is shown,
// and what the day adds up to. A few run against the real repository over an
// in-memory Firestore, where the day boundaries and the session actually
// matter.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/food_entry.dart';
import 'package:nutriscan/models/nutrition_summary.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/screens/history/edit_meal_screen.dart';
import 'package:nutriscan/screens/history/history_screen.dart';
import 'package:nutriscan/screens/home/home_dashboard_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/meal_repository.dart';
import 'package:nutriscan/theme/app_theme.dart';
import 'package:nutriscan/utils/formatters.dart';
import 'package:nutriscan/widgets/app_card.dart';

import 'support/test_doubles.dart';

/// Field order on the meal editor, top to bottom.
const int _caloriesField = 3;

void main() {
  late AppState appState;
  late FakeAuthService auth;

  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day, 12);
  final DateTime yesterday = today.subtract(const Duration(days: 1));
  final DateTime twoDaysAgo = today.subtract(const Duration(days: 2));

  setUp(() {
    appState = AppState();
    auth = FakeAuthService();
  });

  tearDown(() => appState.dispose());

  Future<void> pumpWith(
    WidgetTester tester,
    Widget home,
    MealRepository repository,
  ) async {
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

  /// Pumps History over an in-memory repository holding [meals].
  Future<FakeMealRepository> pumpHistory(
    WidgetTester tester, [
    List<SavedMeal> meals = const <SavedMeal>[],
  ]) async {
    final FakeMealRepository repository = FakeMealRepository(meals: meals);
    addTearDown(repository.dispose);
    await pumpWith(tester, const HistoryScreen(), repository);
    return repository;
  }

  Future<void> previousDay(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
  }

  Future<void> nextDay(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
  }

  Future<void> backToToday(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Today'));
    await tester.pumpAndSettle();
  }

  Future<void> openMealMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Meal actions').first);
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await openMealMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }

  /// Deletes the first meal on the day, confirming the dialog.
  Future<void> deleteFirstMeal(WidgetTester tester) async {
    await openMealMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
  }

  /// The next-day button, which is disabled on today.
  IconButton nextDayButton(WidgetTester tester) {
    return tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Next day'),
        matching: find.byType(IconButton),
      ),
    );
  }

  /// A figure as it appears in the day-total card.
  ///
  /// Phase 2M puts the selected day's calories in the weekly strip as well,
  /// so a bare `find.text` no longer says which of the two copies is meant.
  /// Scoping keeps each assertion below on exactly the figure it was written
  /// for, with the same value and the same count.
  Finder inDayTotal(String value) {
    return find.descendant(
      of: find.ancestor(
        of: find.text('Day total'),
        matching: find.byType(AppCard),
      ),
      matching: find.text(value),
    );
  }

  group('Navigating', () {
    testWidgets('1. History opens on today', (WidgetTester tester) async {
      await pumpHistory(tester, <SavedMeal>[
        buildSavedMeal(id: 'a', createdAt: today, foodName: 'Lunch'),
      ]);

      expect(find.text('Today'), findsOneWidget);
      // Nothing to go back from yet, so no return-to-today action.
      expect(find.widgetWithText(TextButton, 'Today'), findsNothing);
    });

    testWidgets('2. today shows today\'s meals', (WidgetTester tester) async {
      final FakeMealRepository repository = await pumpHistory(
        tester,
        <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Lunch'),
          buildSavedMeal(id: 'b', createdAt: yesterday, foodName: 'Dinner'),
        ],
      );

      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Dinner'), findsNothing);
      // Only the day on screen was asked for.
      expect(repository.datesRequested, <DateTime>[
        DateTime(today.year, today.month, today.day),
      ]);
    });

    testWidgets('3. the previous day shows that day\'s meals', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester, <SavedMeal>[
        buildSavedMeal(id: 'a', createdAt: today, foodName: 'Lunch'),
        buildSavedMeal(id: 'b', createdAt: yesterday, foodName: 'Dinner'),
      ]);

      await previousDay(tester);

      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.text('Lunch'), findsNothing);
    });

    testWidgets('4. the next day comes back to today', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester, <SavedMeal>[
        buildSavedMeal(id: 'a', createdAt: today, foodName: 'Lunch'),
        buildSavedMeal(id: 'b', createdAt: yesterday, foodName: 'Dinner'),
      ]);

      await previousDay(tester);
      await nextDay(tester);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Dinner'), findsNothing);
    });

    testWidgets('5. tomorrow cannot be reached', (WidgetTester tester) async {
      await pumpHistory(tester, <SavedMeal>[
        buildSavedMeal(id: 'a', createdAt: today, foodName: 'Lunch'),
      ]);

      // On today the forward button is disabled outright.
      expect(nextDayButton(tester).onPressed, isNull);
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);

      // It comes back the moment there is a day to return to.
      await previousDay(tester);
      expect(nextDayButton(tester).onPressed, isNotNull);
    });

    testWidgets('6. the date picker jumps to a past day', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester, <SavedMeal>[
        buildSavedMeal(id: 'a', createdAt: today, foodName: 'Lunch'),
      ]);

      // The first of the month has no earlier day in view, so the target is
      // today there - either way the picker's own choice is what is checked.
      final DateTime target = today.day > 1
          ? today.subtract(const Duration(days: 1))
          : today;

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await tester.tap(find.text('${target.day}').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text(Formatters.day(target)), findsWidgets);
    });

    testWidgets('7. the label names the day being shown', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester);

      expect(find.text('Today'), findsOneWidget);
      await previousDay(tester);
      expect(find.text('Yesterday'), findsOneWidget);
      await previousDay(tester);
      expect(find.text(Formatters.day(twoDaysAgo)), findsOneWidget);
    });

    testWidgets('8. a day with nothing on it says so', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester, <SavedMeal>[
        buildSavedMeal(id: 'a', createdAt: today, foodName: 'Lunch'),
      ]);

      await previousDay(tester);

      expect(find.text('No meals on this day.'), findsOneWidget);
      expect(find.text('Lunch'), findsNothing);
    });

    testWidgets('24. Today returns after browsing older days', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester, <SavedMeal>[
        buildSavedMeal(id: 'a', createdAt: today, foodName: 'Lunch'),
      ]);

      await previousDay(tester);
      await previousDay(tester);
      await previousDay(tester);
      expect(find.text('Lunch'), findsNothing);

      await backToToday(tester);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Today'), findsNothing);
    });

    testWidgets('19. days do not leak into each other', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester, <SavedMeal>[
        buildSavedMeal(id: 'a', createdAt: today, foodName: 'Today meal'),
        buildSavedMeal(
          id: 'b',
          createdAt: yesterday,
          foodName: 'Yesterday meal',
        ),
        buildSavedMeal(id: 'c', createdAt: twoDaysAgo, foodName: 'Older meal'),
      ]);

      for (final (String shown, List<String> hidden)
          in <(String, List<String>)>[
            ('Today meal', <String>['Yesterday meal', 'Older meal']),
          ]) {
        expect(find.text(shown), findsOneWidget);
        for (final String other in hidden) {
          expect(find.text(other), findsNothing);
        }
      }

      await previousDay(tester);
      expect(find.text('Yesterday meal'), findsOneWidget);
      expect(find.text('Today meal'), findsNothing);
      expect(find.text('Older meal'), findsNothing);

      await previousDay(tester);
      expect(find.text('Older meal'), findsOneWidget);
      expect(find.text('Today meal'), findsNothing);
      expect(find.text('Yesterday meal'), findsNothing);
    });
  });

  group('The day\'s totals', () {
    /// Two meals on [day], adding up to 620 kcal, 42 P, 50 C, 15 F, 11 fibre.
    List<SavedMeal> twoMealsOn(DateTime day) {
      return <SavedMeal>[
        SavedMeal(
          id: 'a',
          userId: 'user-a',
          mealType: MealType.lunch,
          aiEstimate: buildAnalysis(calories: 400),
          current: buildAnalysis(
            foodName: 'First',
            calories: 400,
            proteinG: 30,
            carbsG: 20,
            fatG: 10,
            fiberG: 7,
          ),
          isEdited: false,
          createdAt: day,
        ),
        SavedMeal(
          id: 'b',
          userId: 'user-a',
          mealType: MealType.breakfast,
          aiEstimate: buildAnalysis(calories: 220),
          current: buildAnalysis(
            foodName: 'Second',
            calories: 220,
            proteinG: 12,
            carbsG: 30,
            fatG: 5,
            fiberG: 4,
          ),
          isEdited: false,
          createdAt: day.subtract(const Duration(hours: 4)),
        ),
      ];
    }

    testWidgets('9-13. calories, macros and fibre for the day', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester, twoMealsOn(today));

      expect(find.text('Day total'), findsOneWidget);
      expect(inDayTotal('2'), findsOneWidget); // meals
      expect(inDayTotal('620'), findsOneWidget); // calories
      expect(find.text('42 g'), findsOneWidget); // protein
      expect(find.text('50 g'), findsOneWidget); // carbs
      expect(find.text('15 g'), findsOneWidget); // fat
      expect(find.text('11 g'), findsOneWidget); // fibre
    });

    testWidgets('9-13b. an older day totals only its own meals', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester, <SavedMeal>[
        ...twoMealsOn(yesterday),
        buildSavedMeal(id: 'today', createdAt: today, calories: 900),
      ]);

      await previousDay(tester);

      expect(inDayTotal('620'), findsOneWidget);
      expect(find.text('42 g'), findsOneWidget);
      expect(find.text('50 g'), findsOneWidget);
      expect(find.text('15 g'), findsOneWidget);
      expect(find.text('11 g'), findsOneWidget);
      // Today's 900 kcal is nowhere in yesterday's numbers. It does appear
      // in the weekly strip, under today, which is the point of the strip.
      expect(inDayTotal('1520'), findsNothing);
      expect(inDayTotal('900'), findsNothing);
    });

    testWidgets('14. the day\'s totals use the edited values', (
      WidgetTester tester,
    ) async {
      final SavedMeal edited = SavedMeal(
        id: 'a',
        userId: 'user-a',
        mealType: MealType.lunch,
        aiEstimate: buildAnalysis(calories: 400),
        current: buildAnalysis(
          calories: 550,
          proteinG: 30,
          carbsG: 20,
          fatG: 10,
          fiberG: 7,
        ),
        isEdited: true,
        createdAt: today,
      );

      await pumpHistory(tester, <SavedMeal>[edited]);

      // The user's 550, not the model's 400.
      expect(find.text('550'), findsWidgets);
      expect(find.text('400'), findsNothing);
      expect(find.text('AI 400'), findsOneWidget);
    });

    testWidgets('15. a deleted meal leaves the day\'s totals', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = await pumpHistory(
        tester,
        twoMealsOn(today),
      );
      expect(inDayTotal('620'), findsOneWidget);

      await deleteFirstMeal(tester);

      expect(repository.deletedIds, <String>['a']);
      expect(find.text('220'), findsWidgets);
      // Nowhere on the screen at all: the strip dropped it as well.
      expect(find.text('620'), findsNothing);
      expect(inDayTotal('1'), findsOneWidget); // one meal left
    });

    testWidgets('18. today\'s totals match the dashboard\'s', (
      WidgetTester tester,
    ) async {
      final List<SavedMeal> meals = twoMealsOn(today);
      final NutritionSummary expected = totalsFor(
        mealsOnDay(meals, DateTime.now()),
      );

      final FakeMealRepository repository = FakeMealRepository(meals: meals);
      addTearDown(repository.dispose);

      await pumpWith(tester, const HistoryScreen(), repository);
      expect(
        inDayTotal(Formatters.calories(expected.calories)),
        findsOneWidget,
      );
      expect(find.text(Formatters.grams(expected.proteinG)), findsOneWidget);

      await pumpWith(
        tester,
        HomeDashboardScreen(onScanPressed: () {}, onSeeAllMealsPressed: () {}),
        repository,
      );
      expect(
        find.text('${Formatters.calories(expected.calories)} kcal'),
        findsOneWidget,
      );
      expect(find.text(Formatters.grams(expected.proteinG)), findsOneWidget);
    });
  });

  group('Editing and deleting on a day', () {
    testWidgets('16, 21. an edit refreshes the day it was made on', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = await pumpHistory(
        tester,
        <SavedMeal>[
          buildSavedMeal(
            id: 'a',
            createdAt: yesterday,
            foodName: 'Porridge',
            calories: 580,
          ),
        ],
      );

      await previousDay(tester);
      await openEditor(tester);
      expect(find.byType(EditMealScreen), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(_caloriesField),
        '300',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Back on yesterday, showing the new numbers without a manual reload.
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('300'), findsWidgets);
      expect(find.text('580'), findsNothing);
      expect(repository.meals.single.current.calories, 300);
    });

    testWidgets('17, 22. a delete refreshes the day it was made on', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = await pumpHistory(
        tester,
        <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: yesterday, foodName: 'Porridge'),
          buildSavedMeal(id: 'b', createdAt: today, foodName: 'Lunch'),
        ],
      );

      await previousDay(tester);
      expect(find.text('Porridge'), findsOneWidget);

      await deleteFirstMeal(tester);

      expect(repository.deletedIds, <String>['a']);
      expect(find.text('Porridge'), findsNothing);
      expect(find.text('No meals on this day.'), findsOneWidget);

      // Today is untouched by a delete made on another day.
      await nextDay(tester);
      expect(find.text('Lunch'), findsOneWidget);
    });

    testWidgets('22b. a swipe delete still works on a past day', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = await pumpHistory(
        tester,
        <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: yesterday, foodName: 'Porridge'),
        ],
      );

      await previousDay(tester);
      await tester.drag(find.text('Porridge'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Delete this meal?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, <String>['a']);
      expect(find.text('No meals on this day.'), findsOneWidget);
    });

    testWidgets('23. an empty account still shows the empty state', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester);

      expect(find.text('No meals saved yet.'), findsOneWidget);
    });
  });

  group('Against a real repository', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreMealRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = FirestoreMealRepository(
        authService: auth,
        firestore: firestore,
      );
      // History is only ever reached with a session already established, and
      // reading must never start one, so these begin where the app does.
      auth.beginSession();
    });

    /// Writes a meal straight to the database, on [createdAt].
    Future<void> seed(String id, DateTime createdAt, String name) {
      return firestore
          .collection('users')
          .doc('user-a')
          .collection('meals')
          .doc(id)
          .set(<String, Object?>{
            MealFields.userId: 'user-a',
            MealFields.foodName: name,
            MealFields.mealType: 'lunch',
            MealFields.isEdited: false,
            MealFields.createdAt: Timestamp.fromDate(createdAt),
            MealFields.current: <String, Object?>{
              MealFields.foodName: name,
              MealFields.calories: 400,
              MealFields.portionGrams: 300,
            },
            MealFields.aiEstimate: <String, Object?>{
              MealFields.foodName: name,
              MealFields.calories: 400,
              MealFields.portionGrams: 300,
            },
          });
    }

    testWidgets('20. browsing days starts no new session', (
      WidgetTester tester,
    ) async {
      await seed('a', today, 'Lunch');
      await seed('b', yesterday, 'Dinner');

      await pumpWith(tester, const HistoryScreen(), repository);
      expect(auth.sessionsCreated, 1);

      await previousDay(tester);
      await previousDay(tester);
      await nextDay(tester);
      await backToToday(tester);

      // The same account throughout, and no second session was started.
      expect(auth.sessionsCreated, 1);
      expect(auth.userId, 'user-a');
      expect(auth.isAnonymous, isTrue);
      expect(auth.signedOut, isFalse);
    });

    testWidgets('the real query splits the days the same way', (
      WidgetTester tester,
    ) async {
      await seed('a', today, 'Lunch');
      await seed('b', yesterday, 'Dinner');

      await pumpWith(tester, const HistoryScreen(), repository);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Dinner'), findsNothing);

      await previousDay(tester);
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.text('Lunch'), findsNothing);
    });
  });
}
