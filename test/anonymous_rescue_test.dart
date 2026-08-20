// Tests for the prompt that offers to rescue a temporary account's data
// before the user switches to a different one.
//
// The rescue is entirely a matter of which existing flow the user is steered
// into: upgrading (Phase 2G) keeps everything because the id never changes,
// while signing in elsewhere (Phase 2H) leaves it behind. Nothing here moves,
// copies or deletes a document, and these tests say so explicitly.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/reviewed_meal.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/screens/auth/create_account_screen.dart';
import 'package:nutriscan/screens/auth/sign_in_screen.dart';
import 'package:nutriscan/screens/home/home_dashboard_screen.dart';
import 'package:nutriscan/screens/onboarding/onboarding_screen.dart';
import 'package:nutriscan/screens/profile/profile_screen.dart';
import 'package:nutriscan/services/anonymous_data.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/meal_repository.dart';
import 'package:nutriscan/services/profile_repository.dart';
import 'package:nutriscan/theme/app_theme.dart';

import 'support/test_doubles.dart';

const String _anonymousId = 'uid-temporary';
const String _permanentId = 'uid-somebody-else';
const String _theirEmail = 'sam.reed@example.com';

void main() {
  late AppState appState;
  late FakeAuthService auth;
  late FakeMealRepository meals;
  late FakeProfileRepository profiles;

  setUp(() {
    appState = AppState();
    auth = FakeAuthService(userId: _anonymousId);
    meals = FakeMealRepository();
    profiles = FakeProfileRepository(storedProfile: buildProfile());
  });

  tearDown(() {
    appState.dispose();
    meals.dispose();
    profiles.dispose();
  });

  Widget wrap(Widget screen) {
    return ServicesScope(
      authService: auth,
      mealRepository: meals,
      profileRepository: profiles,
      child: AppScope(
        state: appState,
        child: MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: screen,
        ),
      ),
    );
  }

  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(const ProfileScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> tapSignIn(WidgetTester tester) async {
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();
  }

  /// An anonymous session that has filled in a profile.
  Future<void> beAnonymousWithProfile() async {
    await auth.ensureSignedIn();
    appState.saveProfile(buildProfile());
  }

  group('deciding whether there is anything to protect', () {
    Future<AnonymousData> read() =>
        readAnonymousData(auth: auth, appState: appState, meals: meals);

    test('nobody signed in has nothing to lose', () async {
      final AnonymousData data = await read();

      expect(data.isWorthKeeping, isFalse);
      expect(data.hasProfile, isFalse);
      expect(data.hasMeals, isFalse);
    });

    test('1. a temporary account with nothing saved is not warned', () async {
      await auth.ensureSignedIn();

      final AnonymousData data = await read();

      // A session on its own is not data: a brand new user has nothing to
      // protect and must not be nagged.
      expect(auth.isAnonymous, isTrue);
      expect(data.isWorthKeeping, isFalse);
    });

    test('2. a saved profile is worth keeping', () async {
      await beAnonymousWithProfile();

      final AnonymousData data = await read();

      expect(data.hasProfile, isTrue);
      expect(data.hasMeals, isFalse);
      expect(data.isWorthKeeping, isTrue);
    });

    test('3. saved meals are worth keeping', () async {
      await auth.ensureSignedIn();
      meals.replaceAll(<SavedMeal>[
        buildSavedMeal(id: 'meal-1', createdAt: DateTime.now()),
      ]);

      final AnonymousData data = await read();

      expect(data.hasProfile, isFalse);
      expect(data.hasMeals, isTrue);
      expect(data.isWorthKeeping, isTrue);
    });

    test('18. a permanent account is never treated as temporary', () async {
      await auth.signInWithEmailPassword(
        email: _theirEmail,
        password: 'bluebird77',
      );
      appState.saveProfile(buildProfile());
      meals.replaceAll(<SavedMeal>[
        buildSavedMeal(id: 'meal-1', createdAt: DateTime.now()),
      ]);

      final AnonymousData data = await read();

      // Their data is reachable through their email, so nothing is stranded.
      expect(data.isWorthKeeping, isFalse);
    });

    test('the meal check costs one look, not a full read', () async {
      await beAnonymousWithProfile();

      await read();

      expect(meals.hasAnyMealsCalls, 1);
    });
  });

  group('the rescue prompt', () {
    testWidgets('2. a temporary account with a profile is warned', (
      WidgetTester tester,
    ) async {
      await beAnonymousWithProfile();
      await pumpProfile(tester);

      await tapSignIn(tester);

      expect(find.text('Protect your NutriScan data'), findsOneWidget);
      expect(
        find.textContaining('Your profile is saved on a temporary account'),
        findsOneWidget,
      );
      // Nothing has happened yet.
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.byType(CreateAccountScreen), findsNothing);
    });

    testWidgets('3. saved meals are named in the warning', (
      WidgetTester tester,
    ) async {
      await beAnonymousWithProfile();
      meals.replaceAll(<SavedMeal>[
        buildSavedMeal(id: 'meal-1', createdAt: DateTime.now()),
      ]);
      await pumpProfile(tester);

      await tapSignIn(tester);

      expect(
        find.textContaining('Your profile and saved meals are on a temporary'),
        findsOneWidget,
      );
    });

    testWidgets('4. creating an account is the recommended way out', (
      WidgetTester tester,
    ) async {
      await beAnonymousWithProfile();
      await pumpProfile(tester);

      await tapSignIn(tester);

      // Emphasised, unlike the two plain text buttons beside it.
      expect(
        find.widgetWithText(FilledButton, 'Create an account'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Sign in anyway'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('5. it says the data stays put, not that it is deleted', (
      WidgetTester tester,
    ) async {
      await beAnonymousWithProfile();
      await pumpProfile(tester);

      await tapSignIn(tester);

      expect(
        find.textContaining(
          'stays with the temporary account and will not follow you',
        ),
        findsOneWidget,
      );
      // Nothing is destroyed, so nothing may claim otherwise.
      for (final Text widget in tester.widgetList<Text>(find.byType(Text))) {
        final String label = widget.data ?? '';
        expect(label, isNot(contains('deleted')));
        expect(label, isNot(contains('lost forever')));
        expect(label, isNot(contains('erased')));
      }
    });

    testWidgets('18. a permanent account goes straight to sign-in', (
      WidgetTester tester,
    ) async {
      await auth.signInWithEmailPassword(
        email: 'alex.carter@example.com',
        password: 'sunflower99',
      );
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      // A permanent account has no sign-in link at all - it shows the
      // secured card instead - so there is nothing here to guard.
      expect(find.text('Already have an account? Sign in'), findsNothing);
      expect(find.text('Account secured'), findsOneWidget);
      expect(find.text('Protect your NutriScan data'), findsNothing);
    });

    testWidgets('17. cancelling leaves everything exactly as it was', (
      WidgetTester tester,
    ) async {
      await beAnonymousWithProfile();
      meals.replaceAll(<SavedMeal>[
        buildSavedMeal(id: 'meal-1', createdAt: DateTime.now()),
      ]);
      final String? before = auth.currentUserId;
      await pumpProfile(tester);

      await tapSignIn(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(SignInScreen), findsNothing);
      expect(auth.currentUserId, before);
      expect(auth.isAnonymous, isTrue);
      expect(appState.profile?.name, 'Alex Carter');
      expect(meals.meals, hasLength(1));
      expect(auth.signedInEmails, isEmpty);
    });
  });

  group('rescuing through Create Account', () {
    testWidgets('6. it opens the existing upgrade screen', (
      WidgetTester tester,
    ) async {
      await beAnonymousWithProfile();
      await pumpProfile(tester);

      await tapSignIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Create an account'));
      await tester.pumpAndSettle();

      // Phase 2G's screen, not a second implementation.
      expect(find.byType(CreateAccountScreen), findsOneWidget);
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.text('Keep your data safe'), findsOneWidget);
    });

    testWidgets('7, 8, 9. upgrading keeps the id, profile and meals', (
      WidgetTester tester,
    ) async {
      await beAnonymousWithProfile();
      meals.replaceAll(<SavedMeal>[
        buildSavedMeal(
          id: 'meal-kept',
          createdAt: DateTime.now(),
          foodName: 'Temporary lunch',
        ),
      ]);
      final String? before = auth.currentUserId;
      await pumpProfile(tester);

      await tapSignIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Create an account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'rescued@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'sunflower99');
      await tester.enterText(find.byType(TextFormField).at(2), 'sunflower99');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      // 7. Same account throughout - linking, never replacing.
      expect(auth.currentUserId, before);
      expect(auth.isAnonymous, isFalse);
      // 8 and 9. Nothing was written, moved or removed to achieve it.
      expect(appState.profile?.name, 'Alex Carter');
      expect(meals.meals.single.id, 'meal-kept');
      expect(meals.saveCalls, 0);
      expect(meals.deletedIds, isEmpty);
      expect(profiles.saveCalls, 0);
      expect(profiles.updateCalls, 0);
      // 21. And the account now reads as secured.
      expect(find.text('Account secured'), findsOneWidget);
      expect(find.text('rescued@example.com'), findsOneWidget);
    });
  });

  group('choosing to sign in anyway', () {
    /// Answers as the other account once sign-in has happened.
    void becomeSomebodyElse() {
      auth.existingUserIdOverride = _permanentId;
      profiles.storedProfile = buildProfile(name: 'Sam Reed', weightKg: 92);
      meals.replaceAll(<SavedMeal>[
        buildSavedMeal(
          id: 'their-meal',
          createdAt: DateTime.now(),
          foodName: 'Sam porridge',
          calories: 300,
        ),
      ]);
    }

    testWidgets('10. it opens the existing sign-in screen', (
      WidgetTester tester,
    ) async {
      await beAnonymousWithProfile();
      await pumpProfile(tester);

      await tapSignIn(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Sign in anyway'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('13, 14, 15, 16. the new account brings only its own data', (
      WidgetTester tester,
    ) async {
      await beAnonymousWithProfile();
      meals.replaceAll(<SavedMeal>[
        buildSavedMeal(
          id: 'temporary-meal',
          createdAt: DateTime.now(),
          foodName: 'Temporary lunch',
          calories: 900,
        ),
      ]);
      await pumpProfile(tester);

      await tapSignIn(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Sign in anyway'));
      await tester.pumpAndSettle();

      becomeSomebodyElse();
      await tester.enterText(find.byType(TextFormField).at(0), _theirEmail);
      await tester.enterText(find.byType(TextFormField).at(1), 'bluebird77');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      // 13 and 14. Their id, their profile, their meals.
      expect(auth.currentUserId, _permanentId);
      expect(appState.profile?.name, 'Sam Reed');
      expect(find.byType(HomeDashboardScreen), findsOneWidget);
      expect(find.text('Sam porridge'), findsOneWidget);

      // 15 and 16. Not a trace of the temporary account.
      expect(find.text('Temporary lunch'), findsNothing);
      expect(appState.profile?.weightKg, 92);
    });

    testWidgets('11, 12. nothing of the temporary account is touched', (
      WidgetTester tester,
    ) async {
      await beAnonymousWithProfile();
      meals.replaceAll(<SavedMeal>[
        buildSavedMeal(id: 'temporary-meal', createdAt: DateTime.now()),
      ]);
      await pumpProfile(tester);

      await tapSignIn(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Sign in anyway'));
      await tester.pumpAndSettle();

      becomeSomebodyElse();
      await tester.enterText(find.byType(TextFormField).at(0), _theirEmail);
      await tester.enterText(find.byType(TextFormField).at(1), 'bluebird77');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      // Signing in reads; it never writes. Nothing was migrated or removed.
      expect(meals.saveCalls, 0);
      expect(meals.deletedIds, isEmpty);
      expect(profiles.saveCalls, 0);
      expect(profiles.updateCalls, 0);
      // 24. And no account was deleted to make room.
      expect(auth.signedOut, isFalse);
    });
  });

  group('onboarding', () {
    testWidgets('1. a brand new user is not warned about anything', (
      WidgetTester tester,
    ) async {
      // No session, no profile, no meals - the first-run case.
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Protect your NutriScan data'), findsNothing);
      expect(find.byType(SignInScreen), findsOneWidget);
      // 6. Onboarding itself is untouched.
      expect(auth.currentUserId, isNull);
    });
  });

  group('23. the rescue never moves a document', () {
    late FakeFirebaseFirestore firestore;
    late FakeAuthService realAuth;
    late FirestoreProfileRepository realProfiles;
    late FirestoreMealRepository realMeals;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      realAuth = FakeAuthService(userId: _anonymousId);
      realProfiles = FirestoreProfileRepository(
        authService: realAuth,
        firestore: firestore,
      );
      realMeals = FirestoreMealRepository(
        authService: realAuth,
        firestore: firestore,
      );

      await realAuth.ensureSignedIn();
      await realProfiles.saveProfile(buildProfile(name: 'Temporary User'));
      await realMeals.saveMeal(
        ReviewedMeal.fromAnalysis(buildAnalysis(foodName: 'Temporary lunch')),
      );
    });

    Future<int> docsUnder(String userId, String collection) async {
      final snapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection(collection)
          .get();
      return snapshot.docs.length;
    }

    test('hasAnyMeals answers without writing anything', () async {
      expect(await realMeals.hasAnyMeals(), isTrue);

      expect(await docsUnder(_anonymousId, 'profile'), 1);
      expect(await docsUnder(_anonymousId, 'meals'), 1);
    });

    test('it never invents a session just to look', () async {
      // A read must not bring an account into existence, or a warning check
      // would quietly undo the lazy sign-in the app relies on.
      final FakeAuthService sessionless = FakeAuthService();
      final FirestoreMealRepository repository = FirestoreMealRepository(
        authService: sessionless,
        firestore: firestore,
      );

      expect(await repository.hasAnyMeals(), isFalse);
      expect(sessionless.currentUserId, isNull);
      expect(sessionless.signInCalls, 0);
    });

    test('signing in elsewhere leaves the temporary account intact', () async {
      realAuth.existingUserIdOverride = _permanentId;
      await realAuth.signInWithEmailPassword(
        email: _theirEmail,
        password: 'bluebird77',
      );

      // The new account starts empty; the temporary one keeps everything.
      expect(await realProfiles.getProfile(), isNull);
      expect(await realMeals.watchMeals().first, isEmpty);
      expect(await docsUnder(_anonymousId, 'profile'), 1);
      expect(await docsUnder(_anonymousId, 'meals'), 1);
      expect(await docsUnder(_permanentId, 'profile'), 0);
      expect(await docsUnder(_permanentId, 'meals'), 0);

      final doc = await firestore
          .collection('users')
          .doc(_anonymousId)
          .collection('profile')
          .doc('current')
          .get();
      expect(doc.data()?['name'], 'Temporary User');
    });

    test(
      'upgrading instead keeps the same id, so nothing has to move',
      () async {
        await realAuth.linkEmailPassword(
          email: 'rescued@example.com',
          password: 'sunflower99',
        );

        expect(realAuth.currentUserId, _anonymousId);
        expect(realAuth.isAnonymous, isFalse);
        expect(await docsUnder(_anonymousId, 'profile'), 1);
        expect(await docsUnder(_anonymousId, 'meals'), 1);

        final profile = await realProfiles.getProfile();
        expect(profile?.name, 'Temporary User');
        final meals = await realMeals.watchMeals().first;
        expect(meals.single.current.foodName, 'Temporary lunch');
      },
    );
  });
}
