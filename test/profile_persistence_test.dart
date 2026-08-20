// Tests for the persistent nutrition profile.
//
// The repository is exercised against an in-memory Firestore; the screens are
// driven with fakes. Nothing here touches a real project.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/nutrition_summary.dart';
import 'package:nutriscan/models/saved_profile.dart';
import 'package:nutriscan/models/user_profile.dart';
import 'package:nutriscan/screens/home/home_dashboard_screen.dart';
import 'package:nutriscan/screens/onboarding/onboarding_screen.dart';
import 'package:nutriscan/screens/profile_setup/profile_setup_screen.dart';
import 'package:nutriscan/screens/splash/splash_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/auth_service.dart';
import 'package:nutriscan/services/nutrition_calculator.dart';
import 'package:nutriscan/services/profile_repository.dart';
import 'package:nutriscan/theme/app_theme.dart';

import 'support/test_doubles.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeAuthService auth;
  late FirestoreProfileRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = FakeAuthService(userId: 'user-a');
    repository = FirestoreProfileRepository(
      authService: auth,
      firestore: firestore,
    );
  });

  /// Reads the raw profile document for a user.
  Future<Map<String, dynamic>?> documentFor(String userId) async {
    final snapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('profile')
        .doc('current')
        .get();
    return snapshot.data();
  }

  group('repository', () {
    test('1. a new user has no profile', () async {
      expect(await repository.getProfile(), isNull);
      expect(await repository.watchProfile().first, isNull);
    });

    test('3. saves the profile with calculated targets', () async {
      final UserProfile profile = buildProfile(weightKg: 70);

      await repository.saveProfile(profile);

      final Map<String, dynamic>? doc = await documentFor('user-a');
      expect(doc, isNotNull);
      expect(doc![ProfileFields.uid], 'user-a');
      expect(doc[ProfileFields.name], 'Alex Carter');
      expect(doc[ProfileFields.age], 28);
      expect(doc[ProfileFields.gender], 'male');
      expect(doc[ProfileFields.heightCm], 175.0);
      expect(doc[ProfileFields.weightKg], 70.0);
      expect(doc[ProfileFields.activityLevel], 'moderate');
      expect(doc[ProfileFields.goal], 'maintain');
      expect(doc[ProfileFields.createdAt], isNotNull);
      expect(doc[ProfileFields.updatedAt], isNotNull);

      // The stored targets are the calculator's, not hand-written numbers.
      final NutritionSummary expected = NutritionCalculator.targetsFor(profile);
      expect(doc[ProfileFields.dailyCalories], expected.calories);
      expect(doc[ProfileFields.proteinGrams], expected.proteinG);
      expect(doc[ProfileFields.carbohydratesGrams], expected.carbsG);
      expect(doc[ProfileFields.fatGrams], expected.fatG);
    });

    test('2 and 5. an existing profile is loaded back', () async {
      await repository.saveProfile(buildProfile(name: 'Sam Reed', age: 41));

      final UserProfile? loaded = await repository.getProfile();

      expect(loaded, isNotNull);
      expect(loaded!.name, 'Sam Reed');
      expect(loaded.age, 41);
      expect(loaded.gender, Gender.male);
      expect(loaded.activityLevel, ActivityLevel.moderate);
      expect(loaded.goal, NutritionGoal.maintain);
    });

    test('4 and 8. an update recalculates the stored targets', () async {
      await repository.saveProfile(buildProfile(weightKg: 70));
      final Map<String, dynamic>? before = await documentFor('user-a');

      await repository.updateProfile(buildProfile(weightKg: 68));

      final Map<String, dynamic>? after = await documentFor('user-a');
      final NutritionSummary expected = NutritionCalculator.targetsFor(
        buildProfile(weightKg: 68),
      );

      expect(after![ProfileFields.weightKg], 68.0);
      expect(after[ProfileFields.dailyCalories], expected.calories);
      expect(after[ProfileFields.proteinGrams], expected.proteinG);
      expect(
        after[ProfileFields.dailyCalories],
        isNot(before![ProfileFields.dailyCalories]),
      );
      expect(after[ProfileFields.createdAt], isNotNull);
    });

    test('6. a malformed document is ignored rather than crashing', () async {
      final malformed = <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{ProfileFields.name: ''},
        <String, Object?>{
          ProfileFields.name: 'Alex',
          ProfileFields.age: 'twenty',
        },
        <String, Object?>{
          ProfileFields.name: 'Alex',
          ProfileFields.age: 28,
          ProfileFields.heightCm: 175,
          ProfileFields.weightKg: 70,
          ProfileFields.gender: 'wombat',
          ProfileFields.activityLevel: 'moderate',
          ProfileFields.goal: 'maintain',
        },
        <String, Object?>{
          ProfileFields.name: 'Alex',
          ProfileFields.age: 900,
          ProfileFields.heightCm: 175,
          ProfileFields.weightKg: 70,
          ProfileFields.gender: 'male',
          ProfileFields.activityLevel: 'moderate',
          ProfileFields.goal: 'maintain',
        },
      ];

      for (final Map<String, Object?> data in malformed) {
        await firestore
            .collection('users')
            .doc('user-a')
            .collection('profile')
            .doc('current')
            .set(data);

        // Reads as "no profile", so the app sends the user to setup again.
        expect(await repository.getProfile(), isNull);
      }
    });

    // Moved from `getProfile` to `saveProfile` in Phase 2S-2. Reading no
    // longer asks for a session at all - that is the whole point of the
    // change - so a sign-in failure cannot reach a read any more. Saving a
    // first profile is where the app still establishes one, so the original
    // coverage (a sign-in failure arrives as a retryable repository message,
    // in Firebase's place and never in its words) lives there now.
    test('7. a failure comes back as a retryable message', () async {
      final FirestoreProfileRepository blocked = FirestoreProfileRepository(
        authService: FakeAuthService(
          failure: const AuthFailure('Sign-in is unavailable right now.'),
        ),
        firestore: firestore,
      );

      await expectLater(
        blocked.saveProfile(buildProfile()),
        throwsA(
          isA<ProfileRepositoryFailure>().having(
            (ProfileRepositoryFailure error) => error.message,
            'message',
            'Sign-in is unavailable right now.',
          ),
        ),
      );
      await expectLater(
        blocked.saveProfile(buildProfile()),
        throwsA(isA<ProfileRepositoryFailure>()),
      );
    });

    test('never reads the profile of another user', () async {
      await firestore
          .collection('users')
          .doc('user-b')
          .collection('profile')
          .doc('current')
          .set(<String, Object?>{
            ProfileFields.uid: 'user-b',
            ProfileFields.name: 'Someone Else',
            ProfileFields.age: 50,
            ProfileFields.heightCm: 160,
            ProfileFields.weightKg: 60,
            ProfileFields.gender: 'female',
            ProfileFields.activityLevel: 'light',
            ProfileFields.goal: 'lose',
          });

      expect(await repository.getProfile(), isNull);
    });
  });

  group('startup and screens', () {
    late AppState appState;
    late FakeMealRepository meals;

    setUp(() {
      appState = AppState();
      meals = FakeMealRepository();
    });

    tearDown(() {
      appState.dispose();
      meals.dispose();
    });

    Future<FakeProfileRepository> pumpApp(
      WidgetTester tester, {
      UserProfile? storedProfile,
      ProfileRepositoryFailure? failure,
    }) async {
      final FakeProfileRepository profiles = FakeProfileRepository(
        storedProfile: storedProfile,
      )..failure = failure;
      addTearDown(profiles.dispose);

      // These cases are all about what the splash does with a session that
      // already exists, so establish one first. A launch with no session at
      // all is covered in sign_in_test.dart.
      await auth.ensureSignedIn();

      await tester.binding.setSurfaceSize(const Size(500, 2400));
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
              home: const SplashScreen(),
            ),
          ),
        ),
      );
      return profiles;
    }

    testWidgets('1. a new user is sent to onboarding', (
      WidgetTester tester,
    ) async {
      final FakeProfileRepository profiles = await pumpApp(tester);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(profiles.loadCalls, 1);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(appState.hasProfile, isFalse);
    });

    testWidgets('10. a returning user skips onboarding', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, storedProfile: buildProfile(name: 'Sam Reed'));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsNothing);
      // The dashboard greets the loaded profile by name.
      expect(find.text('Sam Reed'), findsOneWidget);
      expect(appState.profile?.name, 'Sam Reed');
    });

    testWidgets('a startup failure offers a retry instead of guessing', (
      WidgetTester tester,
    ) async {
      // The failure has to be in place before the splash starts loading.
      final FakeProfileRepository profiles = await pumpApp(
        tester,
        failure: const ProfileRepositoryFailure(
          'No connection to the profile database. Please try again.',
        ),
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(
        find.text('No connection to the profile database. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);

      // Once the problem clears, retrying moves the user on.
      profiles.failure = null;
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('9. the dashboard shows targets from the stored profile', (
      WidgetTester tester,
    ) async {
      final UserProfile profile = buildProfile(weightKg: 70);
      appState.saveProfile(profile);

      await tester.binding.setSurfaceSize(const Size(500, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final FakeProfileRepository profiles = FakeProfileRepository(
        storedProfile: profile,
      );
      addTearDown(profiles.dispose);

      await tester.pumpWidget(
        ServicesScope(
          authService: auth,
          mealRepository: meals,
          profileRepository: profiles,
          child: AppScope(
            state: appState,
            child: MaterialApp(
              theme: AppTheme.light,
              home: HomeDashboardScreen(
                onScanPressed: () {},
                onSeeAllMealsPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final NutritionSummary targets = NutritionCalculator.targetsFor(profile);
      expect(find.text('${targets.calories.round()} kcal'), findsOneWidget);
      expect(find.text('of ${targets.proteinG.round()} g'), findsOneWidget);
    });

    testWidgets('8. changing weight moves the dashboard targets', (
      WidgetTester tester,
    ) async {
      appState.saveProfile(buildProfile(weightKg: 70));
      final NutritionSummary before = appState.dailyTargets;

      appState.saveProfile(buildProfile(weightKg: 68));
      final NutritionSummary after = appState.dailyTargets;

      expect(after.calories, isNot(before.calories));
      expect(after.proteinG, isNot(before.proteinG));
      // The numbers come from the calculator, not from the screen.
      expect(
        after.calories,
        NutritionCalculator.targetsFor(buildProfile(weightKg: 68)).calories,
      );
    });
  });

  // Phase 2S-3, H1. The age field accepted a decimal point, the validator read
  // the field as a double and the save path read it as an int. "28.5" passed
  // validation and then threw out of an async callback nobody awaited, so the
  // user tapped Continue and nothing happened at all - on the one screen a new
  // user cannot skip. These pin the two readings together.
  group('the age field', () {
    late AppState appState;
    late FakeMealRepository meals;
    late FakeProfileRepository profiles;

    /// Field order on the profile form, top to bottom.
    const int nameField = 0;
    const int ageField = 1;
    const int heightField = 2;
    const int weightField = 3;

    setUp(() {
      appState = AppState();
      meals = FakeMealRepository();
      profiles = FakeProfileRepository();
    });

    tearDown(() {
      appState.dispose();
      meals.dispose();
      profiles.dispose();
    });

    Future<void> pumpForm(WidgetTester tester) async {
      await auth.ensureSignedIn();
      await tester.binding.setSurfaceSize(const Size(500, 2400));
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
              home: const ProfileSetupScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> enter(WidgetTester tester, int field, String value) async {
      await tester.enterText(find.byType(TextFormField).at(field), value);
      await tester.pump();
    }

    /// Fills every field but the age, which each test supplies itself.
    Future<void> fillAllBut(WidgetTester tester, {required String age}) async {
      await enter(tester, nameField, 'Alex Carter');
      await enter(tester, ageField, age);
      await enter(tester, heightField, '175');
      await enter(tester, weightField, '70');
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
    }

    /// Submits [age] and asserts the form refused it with [message].
    ///
    /// The saveCalls check is the part that matters: a refusal that still
    /// wrote would be no refusal at all.
    Future<void> expectRejected(
      WidgetTester tester, {
      required String age,
      required String message,
    }) async {
      await pumpForm(tester);
      await fillAllBut(tester, age: age);
      await submit(tester);

      expect(find.text(message), findsOneWidget);
      expect(profiles.saveCalls, 0);
      expect(profiles.storedProfile, isNull);
      // Still on the form: Continue must never silently do nothing.
      expect(find.byType(ProfileSetupScreen), findsOneWidget);
    }

    testWidgets('42. an empty age is refused', (WidgetTester tester) async {
      await expectRejected(
        tester,
        age: '',
        message: 'Please enter your age',
      );
    });

    testWidgets('43. an age that is not a number is refused', (
      WidgetTester tester,
    ) async {
      // The field's formatter allows digits and dots, so this is what an
      // unparseable value actually looks like once typed.
      await expectRejected(
        tester,
        age: '1.2.3',
        message: 'Enter age as a whole number of years',
      );
    });

    testWidgets('44. a decimal age is refused rather than thrown on', (
      WidgetTester tester,
    ) async {
      // The exact value from the audit. Before the fix this passed validation
      // and blew up in int.parse; the test would fail on the uncaught
      // exception as well as on the assertions.
      await expectRejected(
        tester,
        age: '28.5',
        message: 'Enter age as a whole number of years',
      );
    });

    testWidgets('45. a trailing decimal point is refused', (
      WidgetTester tester,
    ) async {
      await expectRejected(
        tester,
        age: '10.',
        message: 'Enter age as a whole number of years',
      );
    });

    testWidgets('46. an age below the range is refused', (
      WidgetTester tester,
    ) async {
      await expectRejected(
        tester,
        age: '9',
        message: 'age should be between 10 and 100',
      );
    });

    testWidgets('47. an age above the range is refused', (
      WidgetTester tester,
    ) async {
      await expectRejected(
        tester,
        age: '101',
        message: 'age should be between 10 and 100',
      );
    });

    testWidgets('48. a whole-number age is saved and opens the dashboard', (
      WidgetTester tester,
    ) async {
      await pumpForm(tester);
      await fillAllBut(tester, age: '28');
      await submit(tester);

      expect(profiles.saveCalls, 1);
      expect(profiles.storedProfile?.age, 28);
      expect(appState.profile?.age, 28);
      expect(find.byType(ProfileSetupScreen), findsNothing);
    });

    // The bounds the validator accepted before this change, unchanged by it.
    // One test each: a save replaces the navigation stack, so a second form
    // cannot be pumped into the same one.
    for (final (int number, String age, String edge) in <(int, String, String)>[
      (49, '10', 'youngest'),
      (50, '100', 'oldest'),
    ]) {
      testWidgets('$number. the $edge accepted age still goes through', (
        WidgetTester tester,
      ) async {
        await pumpForm(tester);
        await fillAllBut(tester, age: age);
        await submit(tester);

        expect(profiles.saveCalls, 1);
        expect(profiles.storedProfile?.age, int.parse(age));
        expect(find.byType(ProfileSetupScreen), findsNothing);
      });
    }
  });
}
