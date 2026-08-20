// Tests for Phase 2S-4: how the dashboard reads its meals.
//
// Three things are pinned here, and they are easy to confuse.
//
// The error state: a read that failed must never be drawn as a day with
// nothing in it. "0 kcal" is a claim about what somebody ate, and the app may
// only make it when it actually knows.
//
// The stream lifecycle: the shell rebuilds this screen on every tab change,
// and the streams must survive that. Not because leaving them behind leaked -
// it did not, the old ones were always cancelled - but because rebuilding
// them threw away and re-read the whole history several times a minute.
//
// The split: today's totals and the recent list want different reads. The
// totals need every meal logged today, however many that is. The recent list
// needs the newest few whenever they were eaten. Neither can be served from
// the other, and the tests below say why in both directions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/main_shell.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/screens/home/home_dashboard_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/meal_repository.dart';
import 'package:nutriscan/theme/app_theme.dart';
import 'package:nutriscan/utils/week.dart';

import 'support/test_doubles.dart';

void main() {
  late AppState appState;
  late FakeAuthService auth;

  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day, 12);
  final DateTime yesterday = DateTime(now.year, now.month, now.day - 1, 12);
  final DateTime lastWeek = DateTime(now.year, now.month, now.day - 7, 12);

  setUp(() {
    appState = AppState();
    auth = FakeAuthService()..beginSession();
  });

  tearDown(() => appState.dispose());

  Future<void> pumpWidgetTree(
    WidgetTester tester,
    Widget home,
    FakeMealRepository repository, {
    bool settle = true,
  }) async {
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
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> pumpDashboard(
    WidgetTester tester,
    FakeMealRepository repository, {
    DateTime Function()? clock,
    bool settle = true,
  }) {
    return pumpWidgetTree(
      tester,
      HomeDashboardScreen(
        onScanPressed: () {},
        onSeeAllMealsPressed: () {},
        clock: clock ?? DateTime.now,
      ),
      repository,
      settle: settle,
    );
  }

  Future<void> openTab(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    await tester.pumpAndSettle();
  }

  // ---------------------------------------------------------------------
  // A. The error state
  // ---------------------------------------------------------------------

  group('when the meals cannot be read', () {
    /// A repository whose live reads fail, as Firestore does when the device
    /// is offline with a cold cache or the read is refused.
    FakeMealRepository failing({List<SavedMeal>? meals}) {
      return FakeMealRepository(meals: meals)
        ..watchFailure = const MealRepositoryFailure(
          'No connection to the meal database. Please try again.',
        );
    }

    testWidgets('1. it says so instead of drawing a day of nothing', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(tester, failing());

      expect(
        find.text("Today's meals could not be loaded"),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('2. no calorie total is shown at all', (
      WidgetTester tester,
    ) async {
      // The regression this whole group exists for: a failed read used to be
      // indistinguishable from an empty day, so the screen said the user had
      // eaten nothing.
      await pumpDashboard(tester, failing());

      expect(find.text('0 kcal'), findsNothing);
      expect(find.textContaining('kcal'), findsNothing);
    });

    testWidgets('3. it does not claim the history is empty', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(tester, failing());

      expect(
        find.text('No meals logged yet. Scan your first meal to see it here.'),
        findsNothing,
      );
    });

    testWidgets('4. a failure with meals stored still shows no numbers', (
      WidgetTester tester,
    ) async {
      // The stored meals are unreachable, not absent. Neither the totals nor
      // the recent list may be drawn from a read that did not arrive.
      await pumpDashboard(
        tester,
        failing(
          meals: <SavedMeal>[
            buildSavedMeal(id: 'a', createdAt: today, foodName: 'Chicken'),
          ],
        ),
      );

      expect(find.text("Today's meals could not be loaded"), findsOneWidget);
      expect(find.text('Chicken'), findsNothing);
      expect(find.textContaining('kcal'), findsNothing);
    });

    testWidgets('5. nothing Firebase said reaches the screen', (
      WidgetTester tester,
    ) async {
      // A repository failure carrying wording no user should ever read.
      final FakeMealRepository repository = FakeMealRepository()
        ..watchFailure = const MealRepositoryFailure(
          '[cloud_firestore/permission-denied] Missing or insufficient '
          'permissions for project nutriscan-a66ae',
        );

      await pumpDashboard(tester, repository);

      for (final String leak in <String>[
        'cloud_firestore',
        'permission-denied',
        'Missing or insufficient',
        'nutriscan-a66ae',
        'Exception',
      ]) {
        expect(
          find.textContaining(leak),
          findsNothing,
          reason: '"$leak" must not reach the dashboard',
        );
      }
      expect(find.text("Today's meals could not be loaded"), findsOneWidget);
    });

    testWidgets('6. the scan button still works while the read is broken', (
      WidgetTester tester,
    ) async {
      // The targets and the camera do not depend on the meals, so a failed
      // read must not take the rest of the screen down with it.
      await pumpDashboard(tester, failing());

      expect(find.text('Scan Food'), findsOneWidget);
      expect(find.text('there'), findsOneWidget); // the greeting
    });

    testWidgets('7. Try again recovers once the read works', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = failing(
        meals: <SavedMeal>[
          buildSavedMeal(
            id: 'a',
            createdAt: today,
            calories: 400,
            foodName: 'Chicken salad',
          ),
        ],
      );

      await pumpDashboard(tester, repository);
      expect(find.text("Today's meals could not be loaded"), findsOneWidget);

      // Whatever was wrong is over.
      repository.watchFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text("Today's meals could not be loaded"), findsNothing);
      expect(find.text('400 kcal'), findsOneWidget);
      expect(find.text('Chicken salad'), findsOneWidget);
    });

    testWidgets('8. Try again that fails again says so again', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = failing();

      await pumpDashboard(tester, repository);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text("Today's meals could not be loaded"), findsOneWidget);
      expect(find.text('0 kcal'), findsNothing);
    });
  });

  group('while the meals are still loading', () {
    testWidgets('9. the screen is drawn, without an error', (
      WidgetTester tester,
    ) async {
      // Unchanged from before: waiting shows the frame with zeroes rather
      // than a spinner. What matters is that waiting is not mistaken for
      // failing.
      await pumpDashboard(tester, FakeMealRepository(), settle: false);
      await tester.pump();

      expect(find.text("Today's meals could not be loaded"), findsNothing);
      expect(find.byType(HomeDashboardScreen), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  // B. Stream lifecycle
  // ---------------------------------------------------------------------

  group('the streams the dashboard opens', () {
    testWidgets('10. one of each, not one per build', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );

      await pumpWidgetTree(tester, const MainShell(), repository);

      expect(repository.watchMealsForDayCalls, 1);
      expect(repository.watchRecentMealsCalls, 1);
      // The whole-history read is not used by any screen any more.
      expect(repository.watchMealsCalls, 0);
    });

    testWidgets('11. switching tabs does not reopen them', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );

      await pumpWidgetTree(tester, const MainShell(), repository);

      // The exact journey that used to take watchCalls 1 -> 3 -> 5 -> 7.
      for (int i = 0; i < 3; i++) {
        await openTab(tester, Icons.history_outlined);
        await openTab(tester, Icons.home_outlined);
      }
      // And a tab that is neither, because the shell rebuilds for those too.
      await openTab(tester, Icons.person_outline_rounded);
      await openTab(tester, Icons.home_outlined);

      expect(repository.watchMealsForDayCalls, 1);
      expect(repository.watchRecentMealsCalls, 1);
    });

    testWidgets('12. two live listeners, and never more', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );

      await pumpWidgetTree(tester, const MainShell(), repository);
      for (int i = 0; i < 3; i++) {
        await openTab(tester, Icons.history_outlined);
        await openTab(tester, Icons.home_outlined);
      }

      // One for the day, one for the recent list. A peak above two would
      // mean an old subscription outlived its replacement.
      expect(repository.activeListeners, 2);
      expect(repository.peakListeners, 2);
    });

    testWidgets('13. leaving the shell closes them', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[buildSavedMeal(id: 'a', createdAt: today)],
      );

      await pumpWidgetTree(tester, const MainShell(), repository);
      expect(repository.activeListeners, 2);

      // What sign-out does: the shell is replaced outright.
      await tester.pumpWidget(
        ServicesScope(
          authService: auth,
          mealRepository: repository,
          profileRepository: FakeProfileRepository(),
          child: AppScope(
            state: appState,
            child: const MaterialApp(
              home: Scaffold(body: Text('signed out')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.activeListeners, 0);
    });

    testWidgets('14. the day rolling over reopens the day stream only', (
      WidgetTester tester,
    ) async {
      DateTime clockValue = DateTime(2026, 8, 20, 23, 55);
      final FakeMealRepository repository = FakeMealRepository();

      await pumpDashboard(
        tester,
        repository,
        clock: () => clockValue,
      );
      expect(repository.watchMealsForDayCalls, 1);
      expect(repository.watchRecentMealsCalls, 1);

      // Past midnight, then any rebuild at all.
      clockValue = DateTime(2026, 8, 21, 0, 5);
      await tester.pumpWidget(
        ServicesScope(
          authService: auth,
          mealRepository: repository,
          profileRepository: FakeProfileRepository(),
          child: AppScope(
            state: appState,
            child: MaterialApp(
              theme: AppTheme.light,
              home: HomeDashboardScreen(
                onScanPressed: () {},
                onSeeAllMealsPressed: () {},
                clock: () => clockValue,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The day moved, so the day stream did. The recent list is not tied to
      // a date and has no reason to be reopened.
      expect(repository.watchMealsForDayCalls, 2);
      expect(repository.watchRecentMealsCalls, 1);
      expect(repository.daysWatched.last, DateTime(2026, 8, 21));
    });
  });

  // ---------------------------------------------------------------------
  // C. What each stream is for
  // ---------------------------------------------------------------------

  group("today's totals", () {
    testWidgets('15. add up every meal logged today, however many', (
      WidgetTester tester,
    ) async {
      // Twelve meals in one day. This is the case a limited query cannot
      // serve: a limit of three would have reported 300 kcal.
      await pumpDashboard(
        tester,
        FakeMealRepository(
          meals: <SavedMeal>[
            for (int i = 0; i < 12; i++)
              buildSavedMeal(
                id: 'm$i',
                createdAt: DateTime(now.year, now.month, now.day, 8, i),
                calories: 100,
                proteinG: 10,
                carbsG: 5,
                fatG: 2,
                foodName: 'Meal $i',
              ),
          ],
        ),
      );

      expect(find.text('1200 kcal'), findsOneWidget);
      expect(find.text('300 kcal'), findsNothing);
      expect(find.text('120 g'), findsOneWidget); // protein
      expect(find.text('60 g'), findsOneWidget); // carbs
      expect(find.text('24 g'), findsOneWidget); // fat
    });

    testWidgets('16. leave earlier days out', (WidgetTester tester) async {
      await pumpDashboard(
        tester,
        FakeMealRepository(
          meals: <SavedMeal>[
            buildSavedMeal(id: 'a', createdAt: today, calories: 400),
            buildSavedMeal(id: 'b', createdAt: yesterday, calories: 900),
            buildSavedMeal(id: 'c', createdAt: lastWeek, calories: 750),
          ],
        ),
      );

      expect(find.text('400 kcal'), findsOneWidget);
      // Today plus yesterday, and the whole history: neither is today.
      expect(find.text('1300 kcal'), findsNothing);
      expect(find.text('2050 kcal'), findsNothing);
    });

    testWidgets('17. are asked for by day, not by reading everything', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository();
      await pumpDashboard(tester, repository);

      expect(repository.daysWatched.single, Week.dayOf(DateTime.now()));
      expect(repository.watchMealsCalls, 0);
    });

    testWidgets('18. follow an edit', (WidgetTester tester) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, calories: 400),
        ],
      );
      await pumpDashboard(tester, repository);
      expect(find.text('400 kcal'), findsOneWidget);

      final SavedMeal stored = repository.meals.single;
      await repository.updateMeal(
        stored.withEdits(stored.current.copyWith(calories: 650)),
      );
      await tester.pumpAndSettle();

      expect(find.text('650 kcal'), findsOneWidget);
      expect(find.text('400 kcal'), findsNothing);
    });

    testWidgets('19. drop a deleted meal', (WidgetTester tester) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'a', createdAt: today, calories: 400),
          buildSavedMeal(
            id: 'b',
            createdAt: DateTime(now.year, now.month, now.day, 9),
            calories: 220,
            foodName: 'Toast',
          ),
        ],
      );
      await pumpDashboard(tester, repository);
      expect(find.text('620 kcal'), findsOneWidget);

      await repository.deleteMeal('a');
      await tester.pumpAndSettle();

      expect(find.text('220 kcal'), findsOneWidget);
      expect(find.text('620 kcal'), findsNothing);
    });

    testWidgets('20. an empty day is nought, and says so plainly', (
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

  group('the recent meals list', () {
    testWidgets('21. reaches back past today', (WidgetTester tester) async {
      // The regression the split most easily breaks: somebody who has not
      // eaten yet today still has a history, and should see it.
      await pumpDashboard(
        tester,
        FakeMealRepository(
          meals: <SavedMeal>[
            buildSavedMeal(
              id: 'y',
              createdAt: yesterday,
              foodName: 'Yesterday dinner',
            ),
            buildSavedMeal(
              id: 'w',
              createdAt: lastWeek,
              foodName: 'Last week lunch',
            ),
          ],
        ),
      );

      expect(find.text('Yesterday dinner'), findsOneWidget);
      expect(find.text('Last week lunch'), findsOneWidget);
      // ...while today itself is still empty.
      expect(find.text('0 kcal'), findsOneWidget);
      expect(
        find.text('No meals logged yet. Scan your first meal to see it here.'),
        findsNothing,
      );
    });

    testWidgets('22. asks for three and shows three', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          for (int i = 0; i < 8; i++)
            buildSavedMeal(
              id: 'm$i',
              createdAt: DateTime(now.year, now.month, now.day - i, 12),
              foodName: 'Meal $i',
            ),
        ],
      );
      await pumpDashboard(tester, repository);

      expect(repository.recentLimits.single, 3);
      // Newest first: 0, 1, 2 are the three most recent.
      expect(find.text('Meal 0'), findsOneWidget);
      expect(find.text('Meal 1'), findsOneWidget);
      expect(find.text('Meal 2'), findsOneWidget);
      expect(find.text('Meal 3'), findsNothing);
      expect(find.text('Meal 7'), findsNothing);
    });

    testWidgets('23. is ordered newest first', (WidgetTester tester) async {
      await pumpDashboard(
        tester,
        FakeMealRepository(
          meals: <SavedMeal>[
            buildSavedMeal(
              id: 'old',
              createdAt: DateTime(now.year, now.month, now.day, 7),
              foodName: 'Breakfast',
            ),
            buildSavedMeal(
              id: 'new',
              createdAt: DateTime(now.year, now.month, now.day, 19),
              foodName: 'Dinner',
            ),
          ],
        ),
      );

      final double newest = tester.getTopLeft(find.text('Dinner')).dy;
      final double oldest = tester.getTopLeft(find.text('Breakfast')).dy;
      expect(newest, lessThan(oldest));
    });

    testWidgets('24. promotes a fourth meal when one is deleted', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          for (int i = 0; i < 4; i++)
            buildSavedMeal(
              id: 'm$i',
              createdAt: DateTime(now.year, now.month, now.day - i, 12),
              foodName: 'Meal $i',
            ),
        ],
      );
      await pumpDashboard(tester, repository);
      expect(find.text('Meal 3'), findsNothing);

      await repository.deleteMeal('m0');
      await tester.pumpAndSettle();

      expect(find.text('Meal 0'), findsNothing);
      expect(find.text('Meal 3'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  // D. Whose meals these are
  // ---------------------------------------------------------------------

  group('the account the dashboard reads for', () {
    testWidgets('25. browsing it starts no session', (
      WidgetTester tester,
    ) async {
      // A device with no session at all, which is where the old bug lived:
      // a read that signs somebody in creates an account nobody asked for.
      auth = FakeAuthService();
      final FakeMealRepository repository = FakeMealRepository();
      final int before = auth.sessionsCreated;

      await pumpWidgetTree(tester, const MainShell(), repository);
      for (int i = 0; i < 3; i++) {
        await openTab(tester, Icons.history_outlined);
        await openTab(tester, Icons.home_outlined);
      }

      expect(auth.sessionsCreated, before);
      expect(auth.currentUserId, isNull);
      expect(auth.signInCalls, 0);
    });

    testWidgets('26. a new shell reads for whoever is signed in now', (
      WidgetTester tester,
    ) async {
      // Creating the streams once makes "the shell is rebuilt when the user
      // changes" load-bearing, so this is the test that holds it up.
      final FakeMealRepository repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(
            id: 'a',
            createdAt: today,
            calories: 400,
            foodName: 'A meal',
          ),
        ],
      );

      await pumpWidgetTree(tester, const MainShell(), repository);
      expect(find.text('400 kcal'), findsOneWidget);
      expect(find.text('A meal'), findsWidgets);

      // Somebody else signs in: their id, their meals, a fresh shell - which
      // is what pushNamedAndRemoveUntil leaves behind.
      await auth.signInWithEmailPassword(
        email: 'b@example.com',
        password: 'sunflower99',
      );
      repository.replaceAll(<SavedMeal>[
        buildSavedMeal(
          id: 'b',
          createdAt: today,
          calories: 250,
          foodName: 'B meal',
          userId: 'user-b',
        ),
      ]);

      await pumpWidgetTree(tester, const MainShell(), repository);

      expect(find.text('250 kcal'), findsOneWidget);
      expect(find.text('B meal'), findsWidgets);
      expect(find.text('400 kcal'), findsNothing);
      expect(find.text('A meal'), findsNothing);
      // The old pair went with the old shell; the new pair is the new one's.
      expect(repository.activeListeners, 2);
      expect(repository.peakListeners, lessThanOrEqualTo(4));
    });
  });
}
