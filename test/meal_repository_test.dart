// Tests for the Firestore-backed meal repository.
//
// These run the real repository against an in-memory Firestore, so the
// document shape, the query and the scoping to `users/{uid}/meals` are all
// exercised without touching a real project.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/models/food_analysis_result.dart';
import 'package:nutriscan/models/reviewed_meal.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/services/auth_service.dart';
import 'package:nutriscan/services/meal_repository.dart';

import 'support/test_doubles.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeAuthService auth;
  late FirestoreMealRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = FakeAuthService(userId: 'user-a');
    repository = FirestoreMealRepository(
      authService: auth,
      firestore: firestore,
    );
  });

  /// Reads the raw documents stored for a user.
  Future<List<Map<String, dynamic>>> documentsFor(String userId) async {
    final snapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('meals')
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  test('3. saves a meal under the signed-in user', () async {
    final ReviewedMeal meal = ReviewedMeal.fromAnalysis(buildAnalysis());

    final String id = await repository.saveMeal(meal);

    expect(id, isNotEmpty);
    final List<Map<String, dynamic>> docs = await documentsFor('user-a');
    expect(docs, hasLength(1));

    final Map<String, dynamic> doc = docs.single;
    expect(doc[MealFields.userId], 'user-a');
    expect(doc[MealFields.foodName], 'Grilled chicken salad');
    expect(doc[MealFields.isEdited], isFalse);
    expect(doc[MealFields.createdAt], isNotNull);

    // Both versions of the numbers are stored.
    final Map<String, dynamic> current = Map<String, dynamic>.from(
      doc[MealFields.current] as Map,
    );
    final Map<String, dynamic> aiEstimate = Map<String, dynamic>.from(
      doc[MealFields.aiEstimate] as Map,
    );
    expect(current[MealFields.calories], 580);
    expect(aiEstimate[MealFields.calories], 580);
    expect(aiEstimate[MealFields.confidence], 0.85);

    // The image is never written to a document.
    expect(doc.containsKey('imageBase64'), isFalse);
    expect(doc.containsKey('image'), isFalse);
  });

  test('3b. stores the user edit alongside the original estimate', () async {
    final FoodAnalysisResult ai = buildAnalysis(calories: 580);
    final ReviewedMeal edited = ReviewedMeal.fromAnalysis(
      ai,
    ).withEdits(ai.copyWith(calories: 620, foodName: 'Chicken salad, large'));

    await repository.saveMeal(edited);

    final Map<String, dynamic> doc = (await documentsFor('user-a')).single;
    final Map<String, dynamic> current = Map<String, dynamic>.from(
      doc[MealFields.current] as Map,
    );
    final Map<String, dynamic> aiEstimate = Map<String, dynamic>.from(
      doc[MealFields.aiEstimate] as Map,
    );

    expect(doc[MealFields.isEdited], isTrue);
    expect(current[MealFields.calories], 620);
    expect(current[MealFields.foodName], 'Chicken salad, large');
    expect(aiEstimate[MealFields.calories], 580);
    expect(aiEstimate[MealFields.foodName], 'Grilled chicken salad');
  });

  test('4. reads back the current user\'s meals, newest first', () async {
    await repository.saveMeal(
      ReviewedMeal.fromAnalysis(buildAnalysis(foodName: 'Porridge')),
    );
    // Far enough apart to have different server timestamps: back to back the
    // two can land in the same millisecond, which leaves "newest first" with
    // nothing to sort by.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repository.saveMeal(
      ReviewedMeal.fromAnalysis(buildAnalysis(foodName: 'Soup')),
    );

    final List<SavedMeal> meals = await repository.watchMeals().first;

    expect(meals, hasLength(2));
    expect(meals.first.current.foodName, 'Soup');
    expect(meals.last.current.foodName, 'Porridge');
    expect(meals.every((SavedMeal meal) => meal.userId == 'user-a'), isTrue);
  });

  test('4b. never reads another user\'s meals', () async {
    // A meal belonging to somebody else, written straight to the database.
    await firestore.collection('users').doc('user-b').collection('meals').add(
      <String, Object?>{
        MealFields.userId: 'user-b',
        MealFields.foodName: 'Someone else pasta',
        MealFields.isEdited: false,
        MealFields.createdAt: DateTime.now(),
        MealFields.current: <String, Object?>{
          MealFields.foodName: 'Someone else pasta',
          MealFields.calories: 700,
        },
        MealFields.aiEstimate: <String, Object?>{
          MealFields.foodName: 'Someone else pasta',
          MealFields.calories: 700,
        },
      },
    );

    await repository.saveMeal(
      ReviewedMeal.fromAnalysis(buildAnalysis(foodName: 'My lunch')),
    );

    final List<SavedMeal> meals = await repository.watchMeals().first;

    expect(meals, hasLength(1));
    expect(meals.single.current.foodName, 'My lunch');
  });

  test('5. deletes a meal', () async {
    final String id = await repository.saveMeal(
      ReviewedMeal.fromAnalysis(buildAnalysis()),
    );
    expect(await documentsFor('user-a'), hasLength(1));

    await repository.deleteMeal(id);

    expect(await documentsFor('user-a'), isEmpty);
    expect(await repository.watchMeals().first, isEmpty);
  });

  test('6. saving twice with the same id updates one meal', () async {
    final ReviewedMeal meal = ReviewedMeal.fromAnalysis(buildAnalysis());

    final String first = await repository.saveMeal(meal);
    final String second = await repository.saveMeal(meal, mealId: first);

    expect(second, first);
    expect(await documentsFor('user-a'), hasLength(1));
  });

  // The security rules hold `createdAt` immutable once a document exists, so
  // a re-save that restamped it would be refused outright. It must also stay
  // put for its own sake: correcting an estimate is not a reason for a meal to
  // move to a later day.
  test('6c. saving twice with the same id keeps the original createdAt',
      () async {
    final ReviewedMeal meal = ReviewedMeal.fromAnalysis(buildAnalysis());

    final String id = await repository.saveMeal(meal);
    final Object? firstCreatedAt = (await documentsFor(
      'user-a',
    )).single[MealFields.createdAt];
    expect(firstCreatedAt, isNotNull);

    await repository.saveMeal(meal, mealId: id);

    final Map<String, dynamic> stored = (await documentsFor('user-a')).single;
    expect(stored[MealFields.createdAt], firstCreatedAt);
    // Everything else is still written, so a re-save is a full correction.
    expect(stored[MealFields.userId], 'user-a');
    expect(stored[MealFields.aiEstimate], isNotNull);
    expect(stored[MealFields.updatedAt], isNotNull);
  });

  test('6b. saving without an id creates separate meals', () async {
    final ReviewedMeal meal = ReviewedMeal.fromAnalysis(buildAnalysis());

    await repository.saveMeal(meal);
    await repository.saveMeal(meal);

    // Two deliberate saves are two meals; the screen passes the id to avoid
    // this happening by accident.
    expect(await documentsFor('user-a'), hasLength(2));
  });

  test('a failed sign-in surfaces as a retryable repository failure', () async {
    final FirestoreMealRepository blocked = FirestoreMealRepository(
      authService: FakeAuthService(
        failure: const AuthFailure('Sign-in is unavailable right now.'),
      ),
      firestore: firestore,
    );

    await expectLater(
      blocked.saveMeal(ReviewedMeal.fromAnalysis(buildAnalysis())),
      throwsA(
        isA<MealRepositoryFailure>().having(
          (MealRepositoryFailure error) => error.message,
          'message',
          'Sign-in is unavailable right now.',
        ),
      ),
    );
  });

  test('mealsForDate returns only that day\'s meals', () async {
    final DateTime today = DateTime.now();
    await repository.saveMeal(ReviewedMeal.fromAnalysis(buildAnalysis()));

    final List<SavedMeal> todays = await repository.mealsForDate(today);
    final List<SavedMeal> yesterdays = await repository.mealsForDate(
      today.subtract(const Duration(days: 1)),
    );

    expect(todays, hasLength(1));
    expect(yesterdays, isEmpty);
  });

  group('mealsForDate', () {
    final DateTime day = DateTime(2026, 8, 12);

    // Reading a day uses the session the device already has and must never
    // start one, so these begin where the app does: already signed in.
    setUp(() => auth.beginSession());

    /// Writes a meal straight to the database at [createdAt], so the exact
    /// instant is under the test's control rather than the server's.
    Future<void> seed(
      String id,
      DateTime createdAt, {
      String userId = 'user-a',
      String name = 'Meal',
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
              MealFields.calories: 400,
            },
            MealFields.aiEstimate: <String, Object?>{
              MealFields.foodName: name,
              MealFields.calories: 400,
            },
          });
    }

    test('returns every meal on that day, newest first', () async {
      await seed('breakfast', day.add(const Duration(hours: 8)), name: 'A');
      await seed('lunch', day.add(const Duration(hours: 13)), name: 'B');
      await seed('dinner', day.add(const Duration(hours: 19)), name: 'C');

      final List<SavedMeal> meals = await repository.mealsForDate(day);

      expect(meals.map((SavedMeal meal) => meal.id), <String>[
        'dinner',
        'lunch',
        'breakfast',
      ]);
    });

    test('leaves the days either side alone', () async {
      await seed('before', day.subtract(const Duration(hours: 1)));
      await seed('on', day.add(const Duration(hours: 12)));
      await seed('after', day.add(const Duration(days: 1, hours: 1)));

      final List<SavedMeal> meals = await repository.mealsForDate(day);

      expect(meals.map((SavedMeal meal) => meal.id), <String>['on']);
    });

    test('takes both ends of the day, and neither midnight beyond', () async {
      // The first and last instants that belong to this day.
      await seed('firstMoment', day);
      await seed(
        'lastMoment',
        day.add(const Duration(days: 1)).subtract(const Duration(seconds: 1)),
      );
      // The instants just outside it, on either side.
      await seed('justBefore', day.subtract(const Duration(seconds: 1)));
      await seed('nextMidnight', day.add(const Duration(days: 1)));

      final List<SavedMeal> meals = await repository.mealsForDate(day);

      expect(meals.map((SavedMeal meal) => meal.id).toSet(), <String>{
        'firstMoment',
        'lastMoment',
      });
    });

    test('reads the day from whatever moment during it is passed', () async {
      await seed('on', day.add(const Duration(hours: 23, minutes: 30)));

      for (final DateTime moment in <DateTime>[
        day,
        day.add(const Duration(hours: 9)),
        day.add(const Duration(hours: 23, minutes: 59)),
      ]) {
        expect(
          (await repository.mealsForDate(moment)).single.id,
          'on',
          reason: '$moment should resolve to the same day',
        );
      }
    });

    test('never returns another users meals for that date', () async {
      await seed('mine', day.add(const Duration(hours: 12)), name: 'Mine');
      await seed(
        'theirs',
        day.add(const Duration(hours: 12)),
        userId: 'user-b',
        name: 'Theirs',
      );

      final List<SavedMeal> meals = await repository.mealsForDate(day);

      expect(meals, hasLength(1));
      expect(meals.single.id, 'mine');
      expect(meals.single.userId, 'user-a');
    });
  });

  group('mealsForRange', () {
    // Monday 17 to Sunday 23 August 2026.
    final DateTime monday = DateTime(2026, 8, 17);
    final DateTime sunday = DateTime(2026, 8, 23);

    // As above: a range is read against a session that already exists.
    setUp(() => auth.beginSession());

    /// Writes a meal straight to the database at [createdAt].
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
            },
            MealFields.aiEstimate: <String, Object?>{
              MealFields.foodName: name,
              MealFields.calories: calories,
            },
          });
    }

    test('returns every meal in the span, newest first', () async {
      await seed('mon', monday.add(const Duration(hours: 8)));
      await seed('wed', monday.add(const Duration(days: 2, hours: 13)));
      await seed('sun', sunday.add(const Duration(hours: 19)));

      final List<SavedMeal> meals = await repository.mealsForRange(
        monday,
        sunday,
      );

      expect(meals.map((SavedMeal meal) => meal.id), <String>[
        'sun',
        'wed',
        'mon',
      ]);
    });

    test('takes both ends of the span, and neither midnight beyond', () async {
      // The first and last instants that belong to the week.
      await seed('firstMoment', monday);
      await seed(
        'lastMoment',
        sunday.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
      );
      // The instants just outside it, on either side.
      await seed('justBefore', monday.subtract(const Duration(seconds: 1)));
      await seed('nextMonday', sunday.add(const Duration(days: 1)));

      final List<SavedMeal> meals = await repository.mealsForRange(
        monday,
        sunday,
      );

      expect(meals.map((SavedMeal meal) => meal.id).toSet(), <String>{
        'firstMoment',
        'lastMoment',
      });
    });

    test('reads the span from any moment during its end days', () async {
      await seed('mon', monday.add(const Duration(hours: 1)));
      await seed('sun', sunday.add(const Duration(hours: 22)));

      final List<SavedMeal> meals = await repository.mealsForRange(
        monday.add(const Duration(hours: 17, minutes: 30)),
        sunday.add(const Duration(hours: 6)),
      );

      expect(meals.map((SavedMeal meal) => meal.id).toSet(), <String>{
        'sun',
        'mon',
      });
    });

    test('one day asked for twice is that single day', () async {
      await seed('on', monday.add(const Duration(hours: 12)));
      await seed('next', monday.add(const Duration(days: 1, hours: 12)));

      final List<SavedMeal> span = await repository.mealsForRange(
        monday,
        monday,
      );
      final List<SavedMeal> day = await repository.mealsForDate(monday);

      expect(span.map((SavedMeal meal) => meal.id), <String>['on']);
      expect(
        span.map((SavedMeal meal) => meal.id),
        day.map((SavedMeal meal) => meal.id),
      );
    });

    test('a span with nothing in it comes back empty', () async {
      await seed('elsewhere', monday.subtract(const Duration(days: 30)));

      expect(await repository.mealsForRange(monday, sunday), isEmpty);
    });

    test('nothing after the span leaks into it', () async {
      await seed('inside', sunday.add(const Duration(hours: 12)));
      await seed('nextWeek', sunday.add(const Duration(days: 1, hours: 12)));
      await seed('nextMonth', DateTime(2026, 9, 20));

      final List<SavedMeal> meals = await repository.mealsForRange(
        monday,
        sunday,
      );

      expect(meals.map((SavedMeal meal) => meal.id), <String>['inside']);
    });

    test('never returns another users meals in the span', () async {
      await seed('mine', monday.add(const Duration(hours: 12)), name: 'Mine');
      await seed(
        'theirs',
        monday.add(const Duration(hours: 12)),
        userId: 'user-b',
        name: 'Theirs',
      );

      final List<SavedMeal> meals = await repository.mealsForRange(
        monday,
        sunday,
      );

      expect(meals, hasLength(1));
      expect(meals.single.id, 'mine');
      expect(meals.single.userId, 'user-a');
    });

    test('every meal in the span counts exactly once', () async {
      await seed('mon', monday.add(const Duration(hours: 12)), calories: 400);
      await seed(
        'tue',
        monday.add(const Duration(days: 1, hours: 12)),
        calories: 250,
      );

      final List<SavedMeal> meals = await repository.mealsForRange(
        monday,
        sunday,
      );

      // The query itself returns each document once...
      expect(
        meals.map((SavedMeal meal) => meal.id).toSet(),
        hasLength(meals.length),
      );
      expect(totalsFor(meals).calories, 650);
      // ...and a list that somehow holds them twice still adds up to one week.
      expect(totalsFor(<SavedMeal>[...meals, ...meals]).calories, 650);
    });
  });

  // Phase 2S-3, DST. The range used to end at `midnight + Duration(days: 1)`,
  // which is 24 real hours - not the next midnight. On the day the clocks go
  // back a local day is 25 hours long, so the range stopped an hour early and
  // the last hour of the day fell into no day at all; going forward it is 23
  // hours, so the range ran an hour into the next day and counted its first
  // meals twice.
  //
  // These pin the boundary to the calendar rather than to a duration. Both
  // hold in every zone, and in one that observes daylight saving they are
  // what fails if the arithmetic goes back to counting hours. This machine is
  // UTC+8 with no transitions, so they cannot reproduce the fault here - they
  // exist to stop it being reintroduced where it does bite.
  group('day boundaries are calendar days', () {
    final DateTime day = DateTime(2026, 10, 25);

    setUp(() => auth.beginSession());

    Future<void> seed(String id, DateTime createdAt) {
      return firestore
          .collection('users')
          .doc('user-a')
          .collection('meals')
          .doc(id)
          .set(<String, Object?>{
            MealFields.userId: 'user-a',
            MealFields.foodName: 'Meal',
            MealFields.mealType: 'lunch',
            MealFields.isEdited: false,
            MealFields.createdAt: Timestamp.fromDate(createdAt),
            MealFields.current: <String, Object?>{
              MealFields.foodName: 'Meal',
              MealFields.calories: 400,
            },
            MealFields.aiEstimate: <String, Object?>{
              MealFields.foodName: 'Meal',
              MealFields.calories: 400,
            },
          });
    }

    /// The next calendar day, worked out the way the app must: by rolling the
    /// day number over, never by adding 24 hours to a moment.
    DateTime nextMidnight(DateTime d) => DateTime(d.year, d.month, d.day + 1);

    test('the day ends at the next calendar midnight, to the microsecond',
        () async {
      final DateTime end = nextMidnight(day);

      // The last instant that is still this day, and the first that is not.
      await seed('lastMicrosecond', end.subtract(const Duration(microseconds: 1)));
      await seed('nextMidnight', end);

      final List<SavedMeal> meals = await repository.mealsForDate(day);

      expect(meals.map((SavedMeal meal) => meal.id).toSet(), <String>{
        'lastMicrosecond',
      });
    });

    test('the day starts at its own calendar midnight, to the microsecond',
        () async {
      final DateTime start = DateTime(day.year, day.month, day.day);

      await seed('firstMicrosecond', start);
      await seed('justBefore', start.subtract(const Duration(microseconds: 1)));

      final List<SavedMeal> meals = await repository.mealsForDate(day);

      expect(meals.map((SavedMeal meal) => meal.id).toSet(), <String>{
        'firstMicrosecond',
      });
    });

    test('consecutive days meet exactly, with no gap and no overlap', () async {
      // One meal at each day's own midnight, across a run of days. Every one
      // must land in exactly one day: a gap loses a meal, an overlap counts
      // it twice, and both are what the duration arithmetic produced.
      final List<DateTime> days = <DateTime>[
        DateTime(2026, 10, 24),
        DateTime(2026, 10, 25),
        DateTime(2026, 10, 26),
        DateTime(2026, 3, 28),
        DateTime(2026, 3, 29),
        DateTime(2026, 3, 30),
      ];

      for (int i = 0; i < days.length; i++) {
        await seed('midnight-$i', days[i]);
        await seed(
          'lastMoment-$i',
          nextMidnight(days[i]).subtract(const Duration(microseconds: 1)),
        );
      }

      for (int i = 0; i < days.length; i++) {
        final List<SavedMeal> meals = await repository.mealsForDate(days[i]);
        expect(
          meals.map((SavedMeal meal) => meal.id).toSet(),
          <String>{'midnight-$i', 'lastMoment-$i'},
          reason: '${days[i]} should hold exactly its own two meals',
        );
      }
    });

    test('a span ends at the calendar midnight after its last day', () async {
      final DateTime first = DateTime(2026, 3, 23);
      final DateTime last = DateTime(2026, 3, 29);
      final DateTime end = nextMidnight(last);

      await seed('lastMoment', end.subtract(const Duration(microseconds: 1)));
      await seed('afterTheSpan', end);

      final List<SavedMeal> meals = await repository.mealsForRange(first, last);

      expect(meals.map((SavedMeal meal) => meal.id).toSet(), <String>{
        'lastMoment',
      });
    });

    test('the real repository and the fake agree on where a day stops',
        () async {
      // The fake used calendar arithmetic while the real one used a duration,
      // so 310 passing tests could not see the difference. Reading the same
      // meals through both is what keeps them honest.
      final DateTime end = nextMidnight(day);
      final DateTime lastMoment = end.subtract(const Duration(microseconds: 1));

      await seed('lastMoment', lastMoment);
      await seed('nextMidnight', end);

      final FakeMealRepository fake = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'lastMoment', createdAt: lastMoment),
          buildSavedMeal(id: 'nextMidnight', createdAt: end),
        ],
      );
      addTearDown(fake.dispose);

      final Set<String> fromReal = (await repository.mealsForDate(day))
          .map((SavedMeal meal) => meal.id)
          .toSet();
      final Set<String> fromFake = (await fake.mealsForDate(day))
          .map((SavedMeal meal) => meal.id)
          .toSet();

      expect(fromReal, <String>{'lastMoment'});
      expect(fromFake, fromReal);
    });
  });

  // Phase 2S-4. The dashboard used to read the whole collection to draw
  // three rows and one day's totals. These are the two bounded reads that
  // replaced it: one day, complete; and the newest few, whenever they were.
  group('the dashboard reads', () {
    final DateTime day = DateTime(2026, 8, 20);

    // Both are reads, so they use the session the device already has and
    // must never start one - the same rule every other read here follows.
    setUp(() => auth.beginSession());

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
            },
            MealFields.aiEstimate: <String, Object?>{
              MealFields.foodName: name,
              MealFields.calories: calories,
            },
          });
    }

    group('watchMealsForDay', () {
      test('returns every meal on the day, newest first', () async {
        await seed('breakfast', day.add(const Duration(hours: 8)), name: 'A');
        await seed('lunch', day.add(const Duration(hours: 13)), name: 'B');
        await seed('dinner', day.add(const Duration(hours: 19)), name: 'C');

        final List<SavedMeal> meals = await repository
            .watchMealsForDay(day)
            .first;

        expect(meals.map((SavedMeal meal) => meal.id), <String>[
          'dinner',
          'lunch',
          'breakfast',
        ]);
      });

      test('is not limited, so a busy day still adds up', () async {
        // The reason the recent-meals query cannot serve the totals.
        for (int i = 0; i < 12; i++) {
          await seed('m$i', day.add(Duration(hours: 7, minutes: i)));
        }

        final List<SavedMeal> meals = await repository
            .watchMealsForDay(day)
            .first;

        expect(meals, hasLength(12));
        expect(totalsFor(meals).calories, 4800);
      });

      test('leaves the days either side alone', () async {
        await seed('before', day.subtract(const Duration(hours: 1)));
        await seed('on', day.add(const Duration(hours: 12)));
        await seed('after', DateTime(2026, 8, 21, 1));

        final List<SavedMeal> meals = await repository
            .watchMealsForDay(day)
            .first;

        expect(meals.map((SavedMeal meal) => meal.id), <String>['on']);
      });

      test('takes the calendar day, to the microsecond', () async {
        // Same boundary the day and week queries use, worked out the same
        // way - so a device whose clocks change cannot disagree with itself.
        final DateTime end = DateTime(2026, 8, 21);
        await seed('firstMoment', day);
        await seed(
          'lastMoment',
          end.subtract(const Duration(microseconds: 1)),
        );
        await seed('justBefore', day.subtract(const Duration(microseconds: 1)));
        await seed('nextMidnight', end);

        final List<SavedMeal> meals = await repository
            .watchMealsForDay(day)
            .first;

        expect(meals.map((SavedMeal meal) => meal.id).toSet(), <String>{
          'firstMoment',
          'lastMoment',
        });
      });

      test('reads the same day whatever moment during it is passed', () async {
        await seed('on', day.add(const Duration(hours: 15)));

        for (final DateTime moment in <DateTime>[
          day,
          day.add(const Duration(hours: 9)),
          day.add(const Duration(hours: 23, minutes: 59)),
        ]) {
          expect(
            (await repository.watchMealsForDay(moment).first).single.id,
            'on',
            reason: '$moment should resolve to the same day',
          );
        }
      });

      test('agrees with the day History reads', () async {
        await seed('a', day.add(const Duration(hours: 8)));
        await seed('b', day.add(const Duration(hours: 20)));
        await seed('other', DateTime(2026, 8, 19, 20));

        final List<SavedMeal> watched = await repository
            .watchMealsForDay(day)
            .first;
        final List<SavedMeal> fetched = await repository.mealsForDate(day);

        expect(
          watched.map((SavedMeal meal) => meal.id),
          fetched.map((SavedMeal meal) => meal.id),
        );
      });

      test('a day with nothing on it comes back empty', () async {
        await seed('elsewhere', DateTime(2026, 8, 15, 12));

        expect(await repository.watchMealsForDay(day).first, isEmpty);
      });

      test('never returns another user\'s meals', () async {
        await seed('mine', day.add(const Duration(hours: 9)));
        await seed(
          'theirs',
          day.add(const Duration(hours: 10)),
          userId: 'user-b',
          name: 'Not mine',
        );

        final List<SavedMeal> meals = await repository
            .watchMealsForDay(day)
            .first;

        expect(meals.map((SavedMeal meal) => meal.id), <String>['mine']);
      });

      test('with no session it reads nothing and starts nothing', () async {
        await auth.signOut();
        final int before = auth.sessionsCreated;

        expect(await repository.watchMealsForDay(day).first, isEmpty);

        expect(auth.currentUserId, isNull);
        expect(auth.sessionsCreated, before);
      });
    });

    group('watchRecentMeals', () {
      test('returns the newest meals first', () async {
        await seed('old', DateTime(2026, 8, 10, 12), name: 'Old');
        await seed('mid', DateTime(2026, 8, 15, 12), name: 'Mid');
        await seed('new', DateTime(2026, 8, 20, 12), name: 'New');

        final List<SavedMeal> meals = await repository
            .watchRecentMeals()
            .first;

        expect(meals.map((SavedMeal meal) => meal.id), <String>[
          'new',
          'mid',
          'old',
        ]);
      });

      test('stops at three by default, however long the history', () async {
        for (int i = 0; i < 40; i++) {
          await seed('m$i', DateTime(2026, 8, 20 - i, 12));
        }

        final List<SavedMeal> meals = await repository
            .watchRecentMeals()
            .first;

        expect(meals, hasLength(3));
        expect(meals.map((SavedMeal meal) => meal.id), <String>[
          'm0',
          'm1',
          'm2',
        ]);
      });

      test('honours a limit it is given', () async {
        for (int i = 0; i < 10; i++) {
          await seed('m$i', DateTime(2026, 8, 20 - i, 12));
        }

        expect(await repository.watchRecentMeals(limit: 1).first, hasLength(1));
        expect(await repository.watchRecentMeals(limit: 5).first, hasLength(5));
      });

      test('reaches back past today, which is the point of it', () async {
        // Nothing today; the preview must still find something to show.
        await seed('yesterday', DateTime(2026, 8, 19, 19), name: 'Y');
        await seed('lastWeek', DateTime(2026, 8, 13, 19), name: 'W');

        final List<SavedMeal> meals = await repository
            .watchRecentMeals()
            .first;

        expect(meals.map((SavedMeal meal) => meal.id), <String>[
          'yesterday',
          'lastWeek',
        ]);
      });

      test('an empty history comes back empty', () async {
        expect(await repository.watchRecentMeals().first, isEmpty);
      });

      test('never returns another user\'s meals', () async {
        await seed('mine', DateTime(2026, 8, 20, 9));
        await seed(
          'theirs',
          DateTime(2026, 8, 20, 10),
          userId: 'user-b',
          name: 'Not mine',
        );

        final List<SavedMeal> meals = await repository
            .watchRecentMeals()
            .first;

        expect(meals.map((SavedMeal meal) => meal.id), <String>['mine']);
      });

      test('with no session it reads nothing and starts nothing', () async {
        await auth.signOut();
        final int before = auth.sessionsCreated;

        expect(await repository.watchRecentMeals().first, isEmpty);

        expect(auth.currentUserId, isNull);
        expect(auth.sessionsCreated, before);
      });
    });

    test('together they read a fraction of what watchMeals does', () async {
      // Three meals a day for a year, which is the size the audit measured.
      for (int i = 0; i < 1100; i++) {
        await seed(
          'm$i',
          DateTime(2026, 8, 20 - (i ~/ 3), 8 + (i % 3) * 5),
        );
      }

      final int everything = (await repository.watchMeals().first).length;
      final int todayOnly = (await repository
              .watchMealsForDay(DateTime(2026, 8, 20))
              .first)
          .length;
      final int recentOnly = (await repository.watchRecentMeals().first).length;

      expect(everything, 1100);
      expect(todayOnly, 3);
      expect(recentOnly, 3);
      // Six documents where the dashboard used to take eleven hundred.
      expect(todayOnly + recentOnly, lessThan(everything ~/ 100));
    });
  });
}
