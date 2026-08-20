// Tests for the screens that read saved meals: History and the dashboard.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/nutrition_summary.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/screens/history/history_screen.dart';
import 'package:nutriscan/screens/home/home_dashboard_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/meal_repository.dart';
import 'package:nutriscan/theme/app_theme.dart';

import 'support/test_doubles.dart';

void main() {
  late AppState appState;
  late FakeAuthService auth;

  setUp(() {
    appState = AppState();
    auth = FakeAuthService();
  });

  tearDown(() => appState.dispose());

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen,
    FakeMealRepository repository,
  ) async {
    addTearDown(repository.dispose);
    await tester.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ServicesScope(
        authService: auth,
        mealRepository: repository,
        profileRepository: FakeProfileRepository(),
        child: AppScope(
          state: appState,
          child: MaterialApp(theme: AppTheme.light, home: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpDashboard(
    WidgetTester tester,
    FakeMealRepository repository,
  ) {
    return pumpScreen(
      tester,
      HomeDashboardScreen(onScanPressed: () {}, onSeeAllMealsPressed: () {}),
      repository,
    );
  }

  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day, 12);
  final DateTime yesterday = today.subtract(const Duration(days: 1));

  group('History', () {
    testWidgets('9. a saved meal appears in the list', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );

      await pumpScreen(tester, const HistoryScreen(), repository);

      expect(find.text('Chicken salad'), findsOneWidget);
      expect(find.text('580'), findsWidgets);
    });

    testWidgets('10. an empty database shows the empty state', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const HistoryScreen(), FakeMealRepository());

      expect(find.text('No meals saved yet.'), findsOneWidget);
    });

    testWidgets('11. the user\'s edited values are the ones displayed', (
      WidgetTester tester,
    ) async {
      final SavedMeal edited = SavedMeal(
        id: 'a',
        userId: 'user-a',
        mealType: buildSavedMeal(id: 'x', createdAt: today).mealType,
        aiEstimate: buildAnalysis(calories: 580),
        current: buildAnalysis(calories: 620, foodName: 'Chicken salad, large'),
        isEdited: true,
        createdAt: today,
      );

      await pumpScreen(
        tester,
        const HistoryScreen(),
        FakeMealRepository(meals: <SavedMeal>[edited]),
      );

      expect(find.text('Chicken salad, large'), findsOneWidget);
      expect(find.text('620'), findsWidgets);
      expect(find.text('580'), findsNothing);
    });

    testWidgets('12. meals on different days get their own headings', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Today lunch'),
          buildSavedMeal(
            id: 'b',
            createdAt: yesterday,
            foodName: 'Yesterday dinner',
          ),
        ],
      );

      await pumpScreen(tester, const HistoryScreen(), repository);

      // Phase 2L shows one day at a time, so each meal is seen under its own
      // day rather than under a heading in a single list.
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Today lunch'), findsOneWidget);
      expect(find.text('Yesterday dinner'), findsNothing);

      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();

      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Yesterday dinner'), findsOneWidget);
      expect(find.text('Today lunch'), findsNothing);
    });

    testWidgets('a deleted meal leaves the list', (WidgetTester tester) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken salad'),
        ],
      );
      await pumpScreen(tester, const HistoryScreen(), repository);

      await tester.drag(find.text('Chicken salad'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, <String>['a']);
      expect(find.text('No meals saved yet.'), findsOneWidget);
    });
  });

  group('Dashboard', () {
    testWidgets('13. today\'s totals add up the saved meals', (
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
          buildSavedMeal(
            id: 'b',
            createdAt: today,
            calories: 220,
            proteinG: 12,
            carbsG: 30,
            fatG: 5,
          ),
        ],
      );

      await pumpDashboard(tester, repository);

      // 400 + 220 eaten against the default 2000 kcal target.
      expect(find.text('620 kcal'), findsOneWidget);
      expect(find.text('42 g'), findsOneWidget);
      expect(find.text('50 g'), findsOneWidget);
      expect(find.text('15 g'), findsOneWidget);
    });

    testWidgets('14. yesterday\'s meals do not count towards today', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, calories: 400),
          buildSavedMeal(id: 'b', createdAt: yesterday, calories: 900),
        ],
      );

      await pumpDashboard(tester, repository);

      expect(find.text('400 kcal'), findsOneWidget);
      expect(find.text('1300 kcal'), findsNothing);
    });

    testWidgets('15. the same meal twice is only counted once', (
      WidgetTester tester,
    ) async {
      final SavedMeal meal = buildSavedMeal(
        id: 'duplicate',
        createdAt: today,
        calories: 400,
      );
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[meal, meal],
      );

      await pumpDashboard(tester, repository);

      expect(find.text('400 kcal'), findsOneWidget);
      expect(find.text('800 kcal'), findsNothing);
    });

    testWidgets('an empty database shows a prompt instead of meals', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(tester, FakeMealRepository());

      expect(find.text('0 kcal'), findsOneWidget);
      expect(
        find.text('No meals logged yet. Scan your first meal to see it here.'),
        findsOneWidget,
      );
    });
  });

  group('totals', () {
    test('count each meal once and use the reviewed values', () {
      final SavedMeal meal = buildSavedMeal(
        id: 'a',
        createdAt: today,
        calories: 400,
      );

      final NutritionSummary total = totalsFor(<SavedMeal>[meal, meal]);

      expect(total.calories, 400);
    });

    test('mealsOnDay keeps only the requested local day', () {
      final List<SavedMeal> meals = <SavedMeal>[
        buildSavedMeal(id: 'a', createdAt: today),
        buildSavedMeal(id: 'b', createdAt: yesterday),
      ];

      expect(mealsOnDay(meals, today), hasLength(1));
      expect(mealsOnDay(meals, today).single.id, 'a');
    });
  });
}
