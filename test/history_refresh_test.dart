// Tests for Phase 2S-1 (E-1): History catching up when its tab comes back.
//
// The shell keeps all four tabs alive, so History is built once and never
// rebuilt on its own. These check the two things that follow from that: a meal
// saved from another tab has to appear on return without restarting the app,
// and a day that ends while History is out of view has to move the screen on -
// but only for somebody who was actually looking at today.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/main_shell.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/reviewed_meal.dart';
import 'package:nutriscan/screens/history/history_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/meal_repository.dart';
import 'package:nutriscan/theme/app_theme.dart';
import 'package:nutriscan/utils/week.dart';

import 'support/test_doubles.dart';

void main() {
  late AppState appState;
  late FakeAuthService auth;

  setUp(() {
    appState = AppState();
    auth = FakeAuthService();
  });

  tearDown(() => appState.dispose());

  /// Wraps [home] in the scopes every screen expects.
  Future<void> pump(
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

  Future<void> openTab(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    await tester.pumpAndSettle();
  }

  group('Returning to the History tab', () {
    testWidgets(
      '1. a meal saved while another tab was showing appears on return',
      (WidgetTester tester) async {
        // The real repository over an in-memory Firestore, so the meal is
        // written and read back exactly as the app writes and reads it.
        final FirestoreMealRepository repository = FirestoreMealRepository(
          authService: auth,
          firestore: FakeFirebaseFirestore(),
        );

        await pump(tester, const MainShell(), repository);
        await openTab(tester, Icons.history_outlined);
        expect(find.text('No meals saved yet.'), findsOneWidget);

        // Away from History, then saved the way the result screen saves it.
        await openTab(tester, Icons.home_outlined);
        await repository.saveMeal(
          ReviewedMeal.fromAnalysis(buildAnalysis(foodName: 'Omelette')),
        );

        await openTab(tester, Icons.history_outlined);

        // No restart, no navigation trick: the tab came back and caught up.
        expect(find.text('Omelette'), findsWidgets);
        expect(find.text('No meals saved yet.'), findsNothing);
      },
    );

    testWidgets('2. the day total counts the meal that was just saved', (
      WidgetTester tester,
    ) async {
      final FirestoreMealRepository repository = FirestoreMealRepository(
        authService: auth,
        firestore: FakeFirebaseFirestore(),
      );

      await pump(tester, const MainShell(), repository);
      await openTab(tester, Icons.history_outlined);
      await openTab(tester, Icons.home_outlined);

      await repository.saveMeal(
        ReviewedMeal.fromAnalysis(buildAnalysis(calories: 640)),
      );
      await openTab(tester, Icons.history_outlined);

      // The summary above the list is built from the day that was re-read.
      expect(find.text('Day total'), findsOneWidget);
      expect(find.text('640'), findsWidgets);
    });

    testWidgets('3. the weekly overview is re-read too', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository();
      addTearDown(repository.dispose);

      await pump(tester, const MainShell(), repository);
      await openTab(tester, Icons.history_outlined);
      expect(repository.datesRequested, hasLength(1));
      expect(repository.rangesRequested, hasLength(1));

      await openTab(tester, Icons.home_outlined);
      await openTab(tester, Icons.history_outlined);

      // A meal saved elsewhere belongs to the strip's totals as much as to
      // the list, so both come back.
      expect(repository.datesRequested, hasLength(2));
      expect(repository.rangesRequested, hasLength(2));
    });

    testWidgets('4. nothing is read while History is out of view', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository();
      addTearDown(repository.dispose);

      await pump(tester, const MainShell(), repository);

      // The shell builds all four tabs at once. History has not been opened,
      // so it must not have spent a query.
      expect(repository.datesRequested, isEmpty);
      expect(repository.rangesRequested, isEmpty);

      await openTab(tester, Icons.history_outlined);
      expect(repository.datesRequested, hasLength(1));
    });

    testWidgets('5. a day chosen on purpose is still shown on return', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository();
      addTearDown(repository.dispose);

      await pump(tester, const MainShell(), repository);
      await openTab(tester, Icons.history_outlined);

      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      final DateTime chosen = repository.datesRequested.last;

      await openTab(tester, Icons.home_outlined);
      await openTab(tester, Icons.history_outlined);

      // Re-read, but the same day: coming back is not the same as going home.
      expect(repository.datesRequested.last, chosen);
      expect(find.text('Yesterday'), findsOneWidget);
    });
  });

  group('A day that ends while History is out of view', () {
    // Two fixed days, so none of this depends on when the suite runs.
    final DateTime firstDay = DateTime(2026, 3, 10, 9);
    final DateTime secondDay = DateTime(2026, 3, 11, 9);

    /// What the screen's clock reads. Moved between pumps to end a day.
    late DateTime clockReads;

    /// Pumps History on its own, so its visibility can be driven directly.
    ///
    /// Pumping the same tree again keeps the state that is under test and
    /// updates the widget, which is exactly what the shell does when the
    /// selected tab changes.
    Future<void> pumpHistory(
      WidgetTester tester,
      MealRepository repository, {
      required bool isActive,
    }) {
      return pump(
        tester,
        HistoryScreen(isActive: isActive, clock: () => clockReads),
        repository,
      );
    }

    testWidgets('6. the screen moves on to the day that has started', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository();
      addTearDown(repository.dispose);

      clockReads = firstDay;
      await pumpHistory(tester, repository, isActive: true);
      expect(repository.datesRequested.last, DateTime(2026, 3, 10));

      // Out of view, and midnight passes.
      await pumpHistory(tester, repository, isActive: false);
      clockReads = secondDay;
      await pumpHistory(tester, repository, isActive: true);

      expect(repository.datesRequested.last, DateTime(2026, 3, 11));
    });

    testWidgets('7. the week comes back around the new day', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository();
      addTearDown(repository.dispose);

      // A Sunday and the Monday after it, so the day that starts belongs to a
      // different week and the strip has to move with it. Both come from the
      // app's own calendar, so this test cannot disagree with the strip about
      // where a week begins.
      final DateTime sunday = Week.endOf(firstDay);
      final DateTime monday = Week.addDays(sunday, 1);

      clockReads = sunday.add(const Duration(hours: 9));
      await pumpHistory(tester, repository, isActive: true);
      final (DateTime, DateTime) weekBefore = repository.rangesRequested.last;

      await pumpHistory(tester, repository, isActive: false);
      clockReads = monday.add(const Duration(hours: 9));
      await pumpHistory(tester, repository, isActive: true);

      final List<DateTime> week = Week.daysOf(monday);
      expect(repository.rangesRequested.last, (week.first, week.last));
      expect(repository.rangesRequested.last, isNot(weekBefore));
    });

    testWidgets('8. a day chosen on purpose does not move with the clock', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository();
      addTearDown(repository.dispose);

      clockReads = firstDay;
      await pumpHistory(tester, repository, isActive: true);

      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(repository.datesRequested.last, DateTime(2026, 3, 9));

      await pumpHistory(tester, repository, isActive: false);
      clockReads = secondDay;
      await pumpHistory(tester, repository, isActive: true);

      // Still the 9th. The clock moved; the person's choice did not.
      expect(repository.datesRequested.last, DateTime(2026, 3, 9));
    });

    testWidgets('9. tapping Today puts the screen back on the clock', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = FakeMealRepository();
      addTearDown(repository.dispose);

      clockReads = firstDay;
      await pumpHistory(tester, repository, isActive: true);

      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Today'));
      await tester.pumpAndSettle();
      expect(repository.datesRequested.last, DateTime(2026, 3, 10));

      await pumpHistory(tester, repository, isActive: false);
      clockReads = secondDay;
      await pumpHistory(tester, repository, isActive: true);

      // Choosing today again re-armed the follow, so the rollover carries.
      expect(repository.datesRequested.last, DateTime(2026, 3, 11));
    });
  });
}
