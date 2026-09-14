// Tests for Phase 2M: the weekly overview above the daily history.
//
// The strip draws seven days and their calories, and choosing one of them
// drives the same selected-day state Phase 2L already had. These cover the
// week maths on its own, the strip on its own, and the two working together
// on the History screen - including that the day view underneath is
// unaffected.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/food_entry.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/screens/history/edit_meal_screen.dart';
import 'package:nutriscan/screens/history/history_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/meal_repository.dart';
import 'package:nutriscan/theme/app_colors.dart';
import 'package:nutriscan/theme/app_theme.dart';
import 'package:nutriscan/utils/formatters.dart';
import 'package:nutriscan/utils/week.dart';
import 'package:nutriscan/widgets/week_strip.dart';

import 'support/test_doubles.dart';

/// Field order on the meal editor, top to bottom.
const int _caloriesField = 3;

void main() {
  late AppState appState;
  late FakeAuthService auth;

  final DateTime now = DateTime.now();
  final DateTime today = Week.dayOf(now);
  final DateTime noon = today.add(const Duration(hours: 12));
  final List<DateTime> thisWeek = Week.daysOf(today);
  final List<DateTime> lastWeek = Week.daysOf(Week.addDays(today, -7));

  setUp(() {
    appState = AppState();
    auth = FakeAuthService();
  });

  tearDown(() => appState.dispose());

  // --- finding things in the strip ---------------------------------------

  /// One day's column in the strip.
  ///
  /// Scoped to the strip because the day list below is keyed by its own date
  /// too, and both would answer to the same key.
  Finder column(DateTime day) => find.descendant(
    of: find.byType(WeekStrip),
    matching: find.byKey(ValueKey<DateTime>(day)),
  );

  /// The calorie figure written under [day], as it is displayed.
  String figureOn(WidgetTester tester, DateTime day) {
    final Iterable<Text> texts = tester.widgetList<Text>(
      find.descendant(of: column(day), matching: find.byType(Text)),
    );
    // Two texts per column: the weekday, then the day's calories.
    return texts.last.data!;
  }

  /// Whether [day] can be opened from the strip.
  bool isSelectable(WidgetTester tester, DateTime day) {
    return tester
            .widget<InkWell>(
              find.descendant(of: column(day), matching: find.byType(InkWell)),
            )
            .onTap !=
        null;
  }

  /// Whether [day] is drawn as the day being shown below.
  bool isMarked(WidgetTester tester, DateTime day) {
    final Container pill = tester.widget<Container>(
      find.descendant(of: column(day), matching: find.byType(Container)).first,
    );
    return (pill.decoration! as BoxDecoration).color == AppColors.primarySoft;
  }

  Future<void> tapDay(WidgetTester tester, DateTime day) async {
    await tester.tap(column(day));
    await tester.pumpAndSettle();
  }

  Future<void> previousWeek(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
  }

  Future<void> nextWeek(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
  }

  IconButton weekButton(WidgetTester tester, String tooltip) {
    return tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );
  }

  // --- pumping -----------------------------------------------------------

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

  Future<FakeMealRepository> pumpHistory(
    WidgetTester tester, [
    List<SavedMeal> meals = const <SavedMeal>[],
  ]) async {
    final FakeMealRepository repository = FakeMealRepository(meals: meals);
    addTearDown(repository.dispose);
    await pumpWith(tester, const HistoryScreen(), repository);
    return repository;
  }

  /// A meal at midday on [day].
  SavedMeal mealOn(DateTime day, {required String id, double calories = 400}) {
    return buildSavedMeal(
      id: id,
      createdAt: day.add(const Duration(hours: 12)),
      foodName: 'Meal $id',
      calories: calories,
    );
  }

  group('Week maths', () {
    test('1. a week is the seven days from Monday to Sunday', () {
      // Wednesday 19 August 2026.
      final List<DateTime> week = Week.daysOf(DateTime(2026, 8, 19));

      expect(week, hasLength(7));
      expect(week.first, DateTime(2026, 8, 17)); // Monday
      expect(week.last, DateTime(2026, 8, 23)); // Sunday
      expect(week.first.weekday, DateTime.monday);
      expect(week.last.weekday, DateTime.sunday);

      for (int i = 1; i < week.length; i++) {
        expect(
          week[i].difference(week[i - 1]).inDays,
          1,
          reason: 'the days must run consecutively',
        );
      }
    });

    test('2. both ends of a week belong to it', () {
      final DateTime monday = DateTime(2026, 8, 17);
      final DateTime sunday = DateTime(2026, 8, 23);

      expect(Week.startOf(monday), monday);
      expect(Week.startOf(sunday), monday);
      expect(Week.endOf(monday), sunday);
      expect(Week.endOf(sunday), sunday);

      // A minute either side falls in the week next door.
      expect(
        Week.startOf(monday.subtract(const Duration(minutes: 1))),
        DateTime(2026, 8, 10),
      );
      expect(
        Week.startOf(sunday.add(const Duration(days: 1))),
        DateTime(2026, 8, 24),
      );
    });

    test('3. any moment during a day resolves to that day\'s week', () {
      final DateTime monday = DateTime(2026, 8, 17);

      for (final DateTime moment in <DateTime>[
        DateTime(2026, 8, 19),
        DateTime(2026, 8, 19, 0, 0, 1),
        DateTime(2026, 8, 19, 23, 59, 59),
      ]) {
        expect(Week.startOf(moment), monday, reason: '$moment');
      }
    });

    test('4. weeks cross months and years without losing a day', () {
      // 1 January 2027 is a Friday, so its week starts in December.
      final List<DateTime> newYear = Week.daysOf(DateTime(2027, 1, 1));
      expect(newYear.first, DateTime(2026, 12, 28));
      expect(newYear.last, DateTime(2027, 1, 3));
      expect(newYear, hasLength(7));

      expect(Week.addDays(DateTime(2026, 8, 31), 1), DateTime(2026, 9));
      expect(Week.addDays(DateTime(2026, 3), -1), DateTime(2026, 2, 28));
    });

    test('5. sameWeek is true only inside one Monday-to-Sunday span', () {
      expect(
        Week.sameWeek(DateTime(2026, 8, 17), DateTime(2026, 8, 23)),
        isTrue,
      );
      expect(
        Week.sameWeek(DateTime(2026, 8, 23), DateTime(2026, 8, 24)),
        isFalse,
      );
    });
  });

  group('The strip', () {
    /// Pumps the strip alone, on a fixed week, so nothing here depends on
    /// what day the tests are run.
    Future<List<DateTime>> pumpStrip(
      WidgetTester tester, {
      required DateTime selected,
      required DateTime todayIs,
      Map<DateTime, double>? calories,
      List<DateTime>? tapped,
      bool nextWeekAllowed = true,
    }) async {
      final List<DateTime> days = Week.daysOf(selected);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: WeekStrip(
              days: days,
              selectedDay: selected,
              today: todayIs,
              caloriesByDay: calories,
              onDaySelected: (DateTime day) => tapped?.add(day),
              onPreviousWeek: () {},
              onNextWeek: nextWeekAllowed ? () {} : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return days;
    }

    testWidgets('6. draws seven days, Monday first, left to right', (
      WidgetTester tester,
    ) async {
      final List<DateTime> days = await pumpStrip(
        tester,
        selected: DateTime(2026, 8, 19),
        todayIs: DateTime(2026, 8, 19),
      );

      double previousEdge = -1;
      for (final DateTime day in days) {
        expect(column(day), findsOneWidget, reason: '$day should be drawn');
        expect(find.text(Formatters.weekday(day)), findsOneWidget);

        final double edge = tester.getTopLeft(column(day)).dx;
        expect(edge, greaterThan(previousEdge), reason: '$day is out of order');
        previousEdge = edge;
      }

      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
      // The span is named once, above the columns.
      expect(find.text('17 – 23 Aug 2026'), findsOneWidget);
    });

    testWidgets('7. each day shows its own calories', (
      WidgetTester tester,
    ) async {
      final DateTime monday = DateTime(2026, 8, 17);

      await pumpStrip(
        tester,
        selected: DateTime(2026, 8, 19),
        todayIs: DateTime(2026, 8, 23),
        calories: <DateTime, double>{
          monday: 1800,
          Week.addDays(monday, 1): 0,
          Week.addDays(monday, 2): 640,
          Week.addDays(monday, 3): 0,
          Week.addDays(monday, 4): 0,
          Week.addDays(monday, 5): 0,
          Week.addDays(monday, 6): 0,
        },
      );

      expect(figureOn(tester, monday), '1800');
      expect(figureOn(tester, Week.addDays(monday, 2)), '640');
    });

    testWidgets('8. a day with nothing on it shows zero and stays open', (
      WidgetTester tester,
    ) async {
      final DateTime monday = DateTime(2026, 8, 17);
      final DateTime tuesday = Week.addDays(monday, 1);
      final List<DateTime> tapped = <DateTime>[];

      await pumpStrip(
        tester,
        selected: monday,
        todayIs: DateTime(2026, 8, 23),
        calories: <DateTime, double>{
          for (final DateTime day in Week.daysOf(monday)) day: 0,
        },
        tapped: tapped,
      );

      expect(figureOn(tester, tuesday), '0');
      expect(isSelectable(tester, tuesday), isTrue);

      await tapDay(tester, tuesday);
      expect(tapped, <DateTime>[tuesday]);
    });

    testWidgets('9. days after today cannot be chosen', (
      WidgetTester tester,
    ) async {
      // Wednesday, so Thursday to Sunday have not happened yet.
      final DateTime wednesday = DateTime(2026, 8, 19);
      final List<DateTime> tapped = <DateTime>[];

      final List<DateTime> days = await pumpStrip(
        tester,
        selected: wednesday,
        todayIs: wednesday,
        calories: <DateTime, double>{
          for (final DateTime day in Week.daysOf(wednesday)) day: 0,
        },
        tapped: tapped,
      );

      for (final DateTime day in days) {
        final bool isPastOrToday = !day.isAfter(wednesday);
        expect(
          isSelectable(tester, day),
          isPastOrToday,
          reason: '${Formatters.weekday(day)} selectable?',
        );
        // A day that has not arrived shows nothing rather than a zero it
        // cannot know, but it keeps its column.
        expect(figureOn(tester, day), isPastOrToday ? '0' : '–');
      }

      await tapDay(tester, Week.addDays(wednesday, 1));
      expect(tapped, isEmpty);
    });

    testWidgets('10. the selected day is marked out', (
      WidgetTester tester,
    ) async {
      final DateTime wednesday = DateTime(2026, 8, 19);

      final List<DateTime> days = await pumpStrip(
        tester,
        selected: wednesday,
        todayIs: DateTime(2026, 8, 23),
      );

      for (final DateTime day in days) {
        expect(
          isMarked(tester, day),
          day == wednesday,
          reason: '${Formatters.weekday(day)} marked?',
        );
      }
    });

    testWidgets('11. an unread week shows no figures at all', (
      WidgetTester tester,
    ) async {
      final List<DateTime> days = await pumpStrip(
        tester,
        selected: DateTime(2026, 8, 19),
        todayIs: DateTime(2026, 8, 23),
      );

      for (final DateTime day in days) {
        expect(figureOn(tester, day), '–');
      }
    });
  });

  group('History and the week together', () {
    testWidgets('12. opens on this week, with today marked', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = await pumpHistory(tester);

      for (final DateTime day in thisWeek) {
        expect(column(day), findsOneWidget);
      }
      expect(isMarked(tester, today), isTrue);
      expect(
        find.text(Formatters.weekRange(thisWeek.first, thisWeek.last)),
        findsOneWidget,
      );

      // Exactly one week was read, and it is Monday to Sunday.
      expect(repository.rangesRequested, <(DateTime, DateTime)>[
        (thisWeek.first, thisWeek.last),
      ]);
    });

    testWidgets('13. every day of the week shows what was eaten on it', (
      WidgetTester tester,
    ) async {
      // Two meals today, plus one on Monday when Monday is a different day.
      // On Mondays, seeding both would put all three meals on today.
      await pumpHistory(tester, <SavedMeal>[
        mealOn(today, id: 'a', calories: 400),
        mealOn(today, id: 'b', calories: 220),
        if (thisWeek.first != today)
          mealOn(thisWeek.first, id: 'c', calories: 510),
      ]);

      expect(figureOn(tester, today), '620');
      if (thisWeek.first != today) {
        expect(figureOn(tester, thisWeek.first), '510');
      }

      // Days with nothing on them read zero, and days still to come read as
      // nothing at all.
      for (final DateTime day in thisWeek) {
        if (day == today || day == thisWeek.first) continue;
        expect(figureOn(tester, day), day.isAfter(today) ? '–' : '0');
      }
    });

    testWidgets('14. the week uses edited values, not the AI estimate', (
      WidgetTester tester,
    ) async {
      final SavedMeal edited = SavedMeal(
        id: 'a',
        userId: 'user-a',
        mealType: MealType.lunch,
        aiEstimate: buildAnalysis(calories: 400),
        current: buildAnalysis(calories: 550),
        isEdited: true,
        createdAt: noon,
      );

      await pumpHistory(tester, <SavedMeal>[edited]);

      expect(figureOn(tester, today), '550');
    });

    testWidgets('15. an edit made on a day moves that day\'s figure', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = await pumpHistory(
        tester,
        <SavedMeal>[mealOn(today, id: 'a', calories: 580)],
      );
      expect(figureOn(tester, today), '580');

      await tester.tap(find.byTooltip('Meal actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(EditMealScreen), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(_caloriesField),
        '300',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(repository.meals.single.current.calories, 300);
      expect(figureOn(tester, today), '300');
    });

    testWidgets('16. a deleted meal leaves the week', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = await pumpHistory(
        tester,
        <SavedMeal>[
          mealOn(today, id: 'a', calories: 400),
          mealOn(today, id: 'b', calories: 220),
        ],
      );
      expect(figureOn(tester, today), '620');

      await tester.tap(find.byTooltip('Meal actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, <String>['a']);
      expect(figureOn(tester, today), '220');
    });

    testWidgets('17. the same meal twice counts once', (
      WidgetTester tester,
    ) async {
      final SavedMeal meal = mealOn(today, id: 'duplicate', calories: 400);

      await pumpHistory(tester, <SavedMeal>[meal, meal]);

      expect(figureOn(tester, today), '400');
    });

    testWidgets('18. tapping a day opens it below, on the same screen', (
      WidgetTester tester,
    ) async {
      final DateTime monday = thisWeek.first;
      // A test run on a Monday has no earlier day in the week to move to.
      if (monday == today) return;

      final FakeMealRepository repository = await pumpHistory(
        tester,
        <SavedMeal>[
          mealOn(today, id: 'a', calories: 400),
          buildSavedMeal(
            id: 'b',
            createdAt: monday.add(const Duration(hours: 12)),
            foodName: 'Monday lunch',
            calories: 510,
          ),
        ],
      );

      await tapDay(tester, monday);

      expect(find.text('Monday lunch'), findsOneWidget);
      expect(find.text(Formatters.day(monday)), findsWidgets);
      expect(isMarked(tester, monday), isTrue);
      expect(isMarked(tester, today), isFalse);
      // The day was opened in place: no second History was pushed.
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(repository.datesRequested.last, monday);
    });

    testWidgets('19. moving inside the week does not re-read it', (
      WidgetTester tester,
    ) async {
      final DateTime monday = thisWeek.first;
      if (monday == today) return;

      final FakeMealRepository repository = await pumpHistory(tester);
      expect(repository.rangesRequested, hasLength(1));

      await tapDay(tester, monday);
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();

      // Still the same seven days, so the one read still stands.
      expect(repository.rangesRequested, hasLength(1));
      expect(repository.datesRequested.length, greaterThan(1));
    });
  });

  group('Moving between weeks', () {
    testWidgets('20. the previous week shows the week before', (
      WidgetTester tester,
    ) async {
      final FakeMealRepository repository = await pumpHistory(
        tester,
        <SavedMeal>[mealOn(lastWeek.first, id: 'a', calories: 700)],
      );

      await previousWeek(tester);

      for (final DateTime day in lastWeek) {
        expect(column(day), findsOneWidget);
      }
      for (final DateTime day in thisWeek) {
        expect(column(day), findsNothing);
      }
      expect(figureOn(tester, lastWeek.first), '700');
      expect(repository.rangesRequested.last, (lastWeek.first, lastWeek.last));

      // The day below moved with the strip, and is still inside it.
      expect(isMarked(tester, Week.addDays(today, -7)), isTrue);
    });

    testWidgets('21. the next week comes back to this one', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester);

      await previousWeek(tester);
      expect(column(thisWeek.first), findsNothing);

      await nextWeek(tester);

      for (final DateTime day in thisWeek) {
        expect(column(day), findsOneWidget);
      }
      expect(isMarked(tester, today), isTrue);
    });

    testWidgets('22. this week is as far forward as the strip goes', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester);

      // Nothing but future days lies beyond it, so the button is disabled.
      expect(weekButton(tester, 'Next week').onPressed, isNull);
      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();
      expect(column(today), findsOneWidget);
      expect(isMarked(tester, today), isTrue);

      // It comes back as soon as there is a week to return from.
      await previousWeek(tester);
      expect(weekButton(tester, 'Next week').onPressed, isNotNull);
    });

    testWidgets('23. coming forward never lands after today', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester);

      // Last Sunday: a week on from it is this Sunday, which for most of the
      // week has not happened yet.
      await previousWeek(tester);
      await tapDay(tester, lastWeek.last);
      expect(isMarked(tester, lastWeek.last), isTrue);

      await nextWeek(tester);

      // Clamped to today rather than overshooting into the future.
      expect(isMarked(tester, today), isTrue);
      expect(find.text('Today'), findsWidgets);
      expect(weekButton(tester, 'Next week').onPressed, isNull);
    });

    testWidgets('24. the strip follows the day arrows across a Monday', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester);

      // Seven days back is the same weekday in the week before.
      for (int i = 0; i < 7; i++) {
        await tester.tap(find.byTooltip('Previous day'));
        await tester.pumpAndSettle();
      }

      final DateTime weekAgo = Week.addDays(today, -7);
      expect(column(weekAgo), findsOneWidget);
      expect(isMarked(tester, weekAgo), isTrue);
      expect(column(today), findsNothing);
    });

    testWidgets('25. the Today button brings the week back too', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester);

      await previousWeek(tester);
      await previousWeek(tester);
      expect(column(today), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Today'));
      await tester.pumpAndSettle();

      expect(column(today), findsOneWidget);
      expect(isMarked(tester, today), isTrue);
      expect(weekButton(tester, 'Next week').onPressed, isNull);
    });

    testWidgets('26. the date picker moves the strip to that week', (
      WidgetTester tester,
    ) async {
      await pumpHistory(tester);

      // The first of this month is always a real, past day to pick.
      final DateTime target = DateTime(today.year, today.month);

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await tester.tap(find.text('1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(column(target), findsOneWidget);
      expect(isMarked(tester, target), isTrue);
      for (final DateTime day in Week.daysOf(target)) {
        expect(column(day), findsOneWidget);
      }
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

    Future<void> seed(
      String id,
      DateTime createdAt, {
      String userId = 'user-a',
      String name = 'Meal',
      double calories = 400,
    }) {
      return firestore
          .collection('users')
          .doc(userId)
          .collection('meals')
          .doc(id)
          .set(<String, Object?>{
            MealFields.userId: userId,
            MealFields.foodName: name,
            MealFields.mealType: 'lunch',
            MealFields.isEdited: false,
            MealFields.createdAt: Timestamp.fromDate(createdAt),
            MealFields.current: <String, Object?>{
              MealFields.foodName: name,
              MealFields.calories: calories,
              MealFields.portionGrams: 300,
            },
            MealFields.aiEstimate: <String, Object?>{
              MealFields.foodName: name,
              MealFields.calories: calories,
              MealFields.portionGrams: 300,
            },
          });
    }

    testWidgets('27. browsing weeks starts no new session', (
      WidgetTester tester,
    ) async {
      await seed('a', noon);

      await pumpWith(tester, const HistoryScreen(), repository);
      expect(auth.sessionsCreated, 1);

      await previousWeek(tester);
      await previousWeek(tester);
      await nextWeek(tester);
      await tapDay(tester, Week.addDays(today, -7));
      await tester.tap(find.widgetWithText(TextButton, 'Today'));
      await tester.pumpAndSettle();

      // The same account throughout, and nothing new was created for it.
      expect(auth.sessionsCreated, 1);
      expect(auth.userId, 'user-a');
      expect(auth.isAnonymous, isTrue);
      expect(auth.signedOut, isFalse);
    });

    testWidgets('28. the week never shows another account\'s meals', (
      WidgetTester tester,
    ) async {
      await seed('mine', noon, name: 'My lunch', calories: 400);
      // Somebody else's meals, on the same days.
      await seed(
        'theirs',
        noon,
        userId: 'user-b',
        name: 'Their lunch',
        calories: 900,
      );
      await seed(
        'theirs-monday',
        thisWeek.first.add(const Duration(hours: 12)),
        userId: 'user-b',
        name: 'Their Monday',
        calories: 900,
      );

      await pumpWith(tester, const HistoryScreen(), repository);

      expect(find.text('My lunch'), findsOneWidget);
      expect(find.text('Their lunch'), findsNothing);
      expect(figureOn(tester, today), '400');
      if (thisWeek.first != today) {
        expect(figureOn(tester, thisWeek.first), '0');
      }
    });

    testWidgets('29. the real range query splits the weeks the same way', (
      WidgetTester tester,
    ) async {
      // The last instant of last week and the first of this one.
      await seed(
        'lastWeek',
        Week.addDays(
          thisWeek.first,
          -1,
        ).add(const Duration(hours: 23, minutes: 59, seconds: 59)),
        name: 'Sunday supper',
        calories: 700,
      );
      await seed(
        'thisWeek',
        thisWeek.first,
        name: 'Monday breakfast',
        calories: 300,
      );

      await pumpWith(tester, const HistoryScreen(), repository);

      // Last week's meal is nowhere in this week's seven days.
      expect(figureOn(tester, thisWeek.first), '300');
      for (final DateTime day in thisWeek.skip(1)) {
        expect(figureOn(tester, day), day.isAfter(today) ? '–' : '0');
      }

      await previousWeek(tester);
      expect(figureOn(tester, lastWeek.last), '700');
    });
  });
}
