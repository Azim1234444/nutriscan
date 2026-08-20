// Tests for Phase 2S-2 (E-5): reading data must never start a session.
//
// A read that quietly signs somebody in turns a lost session into a brand new
// empty one. Everything they saved stays where it was, under an id nothing
// can reach any more, and nothing ever reports a problem - the data simply
// looks as though it has gone. These pin the rule down at the repository, on
// the screens that read, at startup, and across the failed-link case that
// exposed it in the first place.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/main_shell.dart';
import 'package:nutriscan/app/nutriscan_app.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/reviewed_meal.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/models/user_profile.dart';
import 'package:nutriscan/screens/history/history_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/auth_service.dart';
import 'package:nutriscan/services/meal_repository.dart';
import 'package:nutriscan/services/profile_repository.dart';
import 'package:nutriscan/theme/app_theme.dart';
import 'package:nutriscan/utils/week.dart';

import 'support/test_doubles.dart';

/// A profile with every field the repository needs.
UserProfile aProfile() {
  return const UserProfile(
    name: 'Alex Carter',
    age: 30,
    gender: Gender.male,
    heightCm: 180,
    weightKg: 75,
    activityLevel: ActivityLevel.moderate,
    goal: NutritionGoal.maintain,
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeAuthService auth;
  late FirestoreMealRepository meals;
  late FirestoreProfileRepository profiles;

  final DateTime day = DateTime(2026, 8, 20, 12);

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = FakeAuthService(userId: 'user-a');
    meals = FirestoreMealRepository(authService: auth, firestore: firestore);
    profiles = FirestoreProfileRepository(
      authService: auth,
      firestore: firestore,
    );
  });

  /// Writes a meal straight to the database, past the repository.
  Future<void> seedMeal(
    String id,
    DateTime createdAt, {
    String userId = 'user-a',
  }) {
    return firestore
        .collection('users')
        .doc(userId)
        .collection('meals')
        .doc(id)
        .set(<String, Object?>{
          MealFields.userId: userId,
          MealFields.foodName: 'Meal',
          MealFields.mealType: 'lunch',
          MealFields.isEdited: false,
          MealFields.createdAt: Timestamp.fromDate(createdAt),
          MealFields.current: <String, Object?>{
            MealFields.foodName: 'Meal',
            MealFields.calories: 400,
            MealFields.portionGrams: 300,
          },
          MealFields.aiEstimate: <String, Object?>{
            MealFields.foodName: 'Meal',
            MealFields.calories: 400,
            MealFields.portionGrams: 300,
          },
        });
  }

  /// Nothing signed anybody in, and no account came into existence.
  void expectNoSessionStarted() {
    expect(
      auth.currentUserId,
      isNull,
      reason: 'a read left a session behind it',
    );
    expect(auth.signInCalls, 0, reason: 'a read asked to be signed in');
    expect(auth.sessionsCreated, 0, reason: 'a read created an account');
  }

  group('With no session, a read returns nothing and starts nothing', () {
    test('A. the day History reads', () async {
      // Seeded under an id this device is not holding: even so, the read must
      // come back empty rather than signing in to go and look.
      await seedMeal('a', day);

      expect(await meals.mealsForDate(day), isEmpty);
      expectNoSessionStarted();
    });

    test('B. the week History reads', () async {
      await seedMeal('a', day);
      final List<DateTime> week = Week.daysOf(day);

      expect(await meals.mealsForRange(week.first, week.last), isEmpty);
      expectNoSessionStarted();
    });

    test('C. the meal stream the dashboard watches', () async {
      await seedMeal('a', day);

      expect(await meals.watchMeals().first, isEmpty);
      expectNoSessionStarted();
    });

    test('C. the day stream the dashboard totals', () async {
      await seedMeal('a', day);

      expect(await meals.watchMealsForDay(day).first, isEmpty);
      expectNoSessionStarted();
    });

    test('C. the recent-meals stream the dashboard previews', () async {
      await seedMeal('a', day);

      expect(await meals.watchRecentMeals().first, isEmpty);
      expectNoSessionStarted();
    });

    test('D. the profile read', () async {
      expect(await profiles.getProfile(), isNull);
      expectNoSessionStarted();
    });

    test('D. the profile stream', () async {
      expect(await profiles.watchProfile().first, isNull);
      expectNoSessionStarted();
    });

    test('the cheap "is anything saved" check', () async {
      expect(await meals.hasAnyMeals(), isFalse);
      expectNoSessionStarted();
    });
  });

  group('With a session, reads use the one that is already there', () {
    test('E. an anonymous session is reused, never added to', () async {
      auth.beginSession();
      await seedMeal('a', day);

      expect(await meals.mealsForDate(day), hasLength(1));
      expect(await meals.watchMeals().first, hasLength(1));
      expect(await meals.watchMealsForDay(day).first, hasLength(1));
      expect(await meals.watchRecentMeals().first, hasLength(1));
      expect(await profiles.getProfile(), isNull);

      expect(auth.currentUserId, 'user-a');
      expect(auth.isAnonymous, isTrue);
      // Still the one session this device began with: reading added none.
      expect(auth.sessionsCreated, 1);
      expect(auth.signInCalls, 0);
    });

    test('F. a permanent session reads its own account', () async {
      auth.userId = 'permanent-uid';
      auth.beginSession(anonymous: false);
      await seedMeal('mine', day, userId: 'permanent-uid');
      await seedMeal('theirs', day, userId: 'user-a');

      final List<SavedMeal> read = await meals.mealsForDate(day);

      expect(read.map((SavedMeal meal) => meal.id), <String>['mine']);
      expect(auth.currentUserId, 'permanent-uid');
      expect(auth.sessionsCreated, 1);
      expect(auth.signInCalls, 0);
    });
  });

  group('Writing is still where a session deliberately begins', () {
    test('saving a first profile creates the account', () async {
      await profiles.saveProfile(aProfile());

      // The one place the product contract says an account may appear.
      expect(auth.sessionsCreated, 1);
      expect(auth.currentUserId, 'user-a');
    });

    test('saving a first meal creates the account', () async {
      await meals.saveMeal(ReviewedMeal.fromAnalysis(buildAnalysis()));

      expect(auth.sessionsCreated, 1);
      expect(auth.currentUserId, 'user-a');
    });

    test('editing a meal with no session refuses instead', () async {
      await expectLater(
        meals.updateMeal(buildSavedMeal(id: 'a', createdAt: day)),
        throwsA(isA<MealRepositoryFailure>()),
      );
      expectNoSessionStarted();
    });

    test('deleting a meal with no session refuses instead', () async {
      await expectLater(
        meals.deleteMeal('a'),
        throwsA(isA<MealRepositoryFailure>()),
      );
      expectNoSessionStarted();
    });

    test('editing a profile with no session refuses instead', () async {
      await expectLater(
        profiles.updateProfile(aProfile()),
        throwsA(isA<ProfileRepositoryFailure>()),
      );
      expectNoSessionStarted();
    });
  });

  group('On the screens that read', () {
    late AppState appState;

    setUp(() => appState = AppState());
    tearDown(() => appState.dispose());

    Future<void> pump(WidgetTester tester, Widget home) async {
      await tester.binding.setSurfaceSize(const Size(500, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ServicesScope(
          authService: auth,
          mealRepository: meals,
          profileRepository: profiles,
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

    testWidgets('A. History browsed with no session creates no account', (
      WidgetTester tester,
    ) async {
      await seedMeal('a', DateTime.now());

      await pump(tester, const HistoryScreen());
      // Days and weeks, the way somebody looking around would.
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous week'));
      await tester.pumpAndSettle();

      expect(find.text('No meals on this day.'), findsOneWidget);
      expectNoSessionStarted();
    });

    testWidgets('C. the dashboard read with no session creates no account', (
      WidgetTester tester,
    ) async {
      await seedMeal('a', DateTime.now());

      await pump(tester, const MainShell());

      expect(find.text('0 kcal'), findsWidgets);
      expectNoSessionStarted();
    });
  });

  group('G. Launching the app with no session', () {
    testWidgets('leaves onboarding without creating an account', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        NutriScanApp(
          authService: auth,
          mealRepository: meals,
          profileRepository: profiles,
        ),
      );

      // Splash holds for two seconds, then routes on what it found.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('Scan any meal'), findsOneWidget);
      expectNoSessionStarted();
    });
  });

  group('After a link that took the session with it', () {
    // The Phase 2S-1 field case: the upgrade failed, Firebase dropped the
    // session, and the next read quietly built a replacement account on top
    // of the wreckage.
    setUp(() {
      auth.beginSession();
      auth.linkFailure = const AuthSessionLost(
        'The account could not be created, and this device has been signed '
        'out. Nothing has been deleted. Sign in if you already have an '
        'account.',
      );
    });

    test('H. reading afterwards does not build a replacement account',
        () async {
      await seedMeal('a', day);
      final int before = auth.sessionsCreated;

      await expectLater(
        auth.linkEmailPassword(
          email: 'alex@example.com',
          password: 'sunflower99',
        ),
        throwsA(isA<AuthSessionLost>()),
      );
      expect(auth.currentUserId, isNull);

      // Everything History and the dashboard would ask for on the way back.
      expect(await meals.mealsForDate(day), isEmpty);
      expect(await meals.mealsForRange(day, day), isEmpty);
      expect(await meals.watchMeals().first, isEmpty);
      expect(await meals.watchMealsForDay(day).first, isEmpty);
      expect(await meals.watchRecentMeals().first, isEmpty);
      expect(await profiles.getProfile(), isNull);

      expect(
        auth.sessionsCreated,
        before,
        reason: 'a read replaced the lost account with a new one',
      );
      expect(auth.currentUserId, isNull);
    });

    test('I. the stranded data stays exactly where it was', () async {
      await seedMeal('a', day);

      await expectLater(
        auth.linkEmailPassword(
          email: 'alex@example.com',
          password: 'sunflower99',
        ),
        throwsA(isA<AuthSessionLost>()),
      );
      await meals.mealsForDate(day);

      // Nothing was moved, reassigned or deleted - it is simply out of reach
      // until the user signs back in to the account that owns it.
      final QuerySnapshot<Map<String, dynamic>> stored = await firestore
          .collection('users')
          .doc('user-a')
          .collection('meals')
          .get();

      expect(stored.docs, hasLength(1));
      expect(stored.docs.single.data()[MealFields.userId], 'user-a');
    });
  });
}
