// Tests for signing out and switching accounts.
//
// Sign-out is an authentication operation, never a data one, so these check
// two things above all: that nothing stored is touched, and that no trace of
// the account that left can reach the one that arrives.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/main_shell.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/reviewed_meal.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/models/user_profile.dart';
import 'package:nutriscan/screens/auth/create_account_screen.dart';
import 'package:nutriscan/screens/auth/sign_in_screen.dart';
import 'package:nutriscan/screens/home/home_dashboard_screen.dart';
import 'package:nutriscan/screens/onboarding/onboarding_screen.dart';
import 'package:nutriscan/screens/profile/profile_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/auth_service.dart';
import 'package:nutriscan/services/meal_repository.dart';
import 'package:nutriscan/services/profile_repository.dart';
import 'package:nutriscan/theme/app_theme.dart';

import 'support/test_doubles.dart';

/// Two accounts, so nothing can pass between them unnoticed.
const String _userA = 'uid-user-a';
const String _userB = 'uid-user-b';
const String _emailA = 'alex.carter@example.com';
const String _emailB = 'sam.reed@example.com';

void main() {
  late AppState appState;
  late FakeAuthService auth;
  late FakeMealRepository meals;
  late FakeProfileRepository profiles;

  setUp(() {
    appState = AppState();
    auth = FakeAuthService(userId: _userA);
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

  /// Puts the profile screen on a surface tall enough to show everything.
  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(const ProfileScreen()));
    await tester.pumpAndSettle();
  }

  /// Signs in as a permanent user before the screen is built.
  Future<void> beSignedIn(String email) async {
    await auth.signInWithEmailPassword(email: email, password: 'sunflower99');
  }

  Future<void> tapSignOut(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();
  }

  group('what the account section offers', () {
    testWidgets('1, 2. a permanent account is named and can sign out', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile());

      await pumpProfile(tester);

      expect(find.text('Account secured'), findsOneWidget);
      expect(find.text(_emailA), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Sign out'), findsOneWidget);
      // The upgrade offer belongs to anonymous accounts only.
      expect(find.text('Create an account'), findsNothing);
    });

    testWidgets('the user id is never put on screen', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile());

      await pumpProfile(tester);

      for (final Text widget in tester.widgetList<Text>(find.byType(Text))) {
        expect(widget.data ?? '', isNot(contains(_userA)));
      }
    });

    testWidgets('3, 4. an anonymous account keeps upgrade and sign-in', (
      WidgetTester tester,
    ) async {
      appState.saveProfile(buildProfile());

      await pumpProfile(tester);

      // 18 and 19. Phase 2G and 2H offers are both untouched.
      expect(find.text('Create an account'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Already have an account? Sign in'), findsOneWidget);
      expect(find.text('Account secured'), findsNothing);
      // And sign-out is offered here too.
      expect(find.widgetWithText(OutlinedButton, 'Sign out'), findsOneWidget);
    });

    testWidgets('nothing is offered before anyone is signed in', (
      WidgetTester tester,
    ) async {
      auth.anonymous = null;
      appState.saveProfile(buildProfile());

      await pumpProfile(tester);

      expect(find.widgetWithText(OutlinedButton, 'Sign out'), findsNothing);
      expect(find.text('Create Account'), findsNothing);
      expect(find.text('Account secured'), findsNothing);
    });
  });

  group('confirming before signing out', () {
    testWidgets('5. a permanent account is asked first', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      await tapSignOut(tester);

      expect(find.text('Sign out?'), findsOneWidget);
      expect(
        find.text(
          'Your saved meals and profile will remain safely stored in your '
          'account.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      // Nothing has happened yet.
      expect(auth.signedOut, isFalse);
      expect(appState.profile, isNotNull);
    });

    testWidgets('16. a temporary account gets the stronger warning', (
      WidgetTester tester,
    ) async {
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      await tapSignOut(tester);

      expect(find.text('Sign out?'), findsOneWidget);
      expect(
        find.textContaining("You're using a temporary account"),
        findsOneWidget,
      );
      expect(
        find.textContaining('may not be recoverable on this device'),
        findsOneWidget,
      );
      expect(auth.signedOut, isFalse);
    });

    testWidgets('6. cancelling leaves the session exactly as it was', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      await tapSignOut(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(auth.signedOut, isFalse);
      expect(auth.currentUserId, _userA);
      expect(auth.isAnonymous, isFalse);
      expect(appState.profile?.name, 'Alex Carter');
      // Still on the profile, still showing the account.
      expect(find.text('Account secured'), findsOneWidget);
      expect(find.text(_emailA), findsOneWidget);
    });

    testWidgets('34. cancelling leaves an anonymous session active too', (
      WidgetTester tester,
    ) async {
      await auth.ensureSignedIn();
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      await tapSignOut(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(auth.signedOut, isFalse);
      expect(auth.isAnonymous, isTrue);
      expect(find.text('Create an account'), findsOneWidget);
    });

    testWidgets('a failure keeps the user signed in and explains itself', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      auth.signOutFailure = const AuthFailure(
        'No internet connection. Connect and try again.',
      );
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      await tapSignOut(tester);
      await confirm(tester);

      expect(
        find.text('No internet connection. Connect and try again.'),
        findsOneWidget,
      );
      // The session survived, so the profile must not have been dropped.
      expect(auth.currentUserId, _userA);
      expect(appState.profile?.name, 'Alex Carter');
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });

  group('signing out', () {
    testWidgets('7. confirming ends the session', (WidgetTester tester) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      await tapSignOut(tester);
      await confirm(tester);

      expect(auth.signedOut, isTrue);
      expect(auth.currentUserId, isNull);
      expect(auth.currentUserEmail, isNull);
    });

    testWidgets('8, 9. everything held in memory is dropped', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile());
      appState.setPendingMeal(
        ReviewedMeal.fromAnalysis(buildAnalysis(foodName: 'Half-reviewed')),
      );
      await pumpProfile(tester);

      await tapSignOut(tester);
      await confirm(tester);

      expect(appState.profile, isNull);
      expect(appState.hasProfile, isFalse);
      expect(appState.pendingMeal, isNull);
    });

    testWidgets('10, 25. the account screens are gone and cannot come back', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      await tapSignOut(tester);
      await confirm(tester);

      // Landed on the no-session entry point.
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.text('Alex Carter'), findsNothing);
      expect(find.text(_emailA), findsNothing);

      // 25. Nothing is left underneath to go back to.
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator),
      );
      expect(navigator.canPop(), isFalse);
    });

    testWidgets('23, 24. nothing stored is deleted', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      await tapSignOut(tester);
      await confirm(tester);

      // The account still exists as far as the app is concerned - it was
      // never asked to be removed - and no document was written or deleted.
      expect(profiles.storedProfile, isNotNull);
      expect(profiles.saveCalls, 0);
      expect(profiles.updateCalls, 0);
      expect(meals.saveCalls, 0);
      expect(meals.deletedIds, isEmpty);
    });

    testWidgets('21. no session is quietly started in its place', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      await tapSignOut(tester);
      await confirm(tester);
      await tester.pumpAndSettle();

      // Signing out must leave the app with no account at all: creating one
      // here would be the eager-anonymous behaviour coming back.
      expect(auth.currentUserId, isNull);
      expect(auth.isSignedIn, isFalse);
      expect(auth.isAnonymous, isNull);
    });
  });

  group('signing out of the running app', () {
    testWidgets('21. the live meal stream does not start a new session', (
      WidgetTester tester,
    ) async {
      // The dashboard subscribes to watchMeals, which asks for a user id.
      // Signing out from the profile tab while that subscription is alive is
      // the one place an anonymous account could quietly reappear.
      await tester.binding.setSurfaceSize(const Size(500, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile());
      meals.replaceAll(<SavedMeal>[
        buildSavedMeal(id: 'meal-a', createdAt: DateTime.now()),
      ]);

      await tester.pumpWidget(wrap(const MainShell()));
      await tester.pumpAndSettle();
      expect(find.byType(HomeDashboardScreen), findsOneWidget);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      final int signInsBefore = auth.signInCalls;
      await tapSignOut(tester);
      await confirm(tester);
      await tester.pumpAndSettle();

      expect(auth.signedOut, isTrue);
      expect(auth.currentUserId, isNull);
      expect(auth.isSignedIn, isFalse);
      expect(auth.signInCalls, lessThanOrEqualTo(signInsBefore));
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(MainShell), findsNothing);
    });
  });

  group('switching accounts', () {
    /// Signs A out from the profile screen, then signs B in from onboarding.
    Future<void> switchToUserB(WidgetTester tester) async {
      await tapSignOut(tester);
      await confirm(tester);

      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), _emailB);
      await tester.enterText(find.byType(TextFormField).at(1), 'bluebird77');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
    }

    testWidgets('11, 13, 14. B sees B, and never a trace of A', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile(name: 'Alex Carter', weightKg: 55));
      await pumpProfile(tester);

      // From here on, the repository answers as user B would.
      auth.existingUserIdOverride = _userB;
      profiles.storedProfile = buildProfile(name: 'Sam Reed', weightKg: 92);

      await switchToUserB(tester);

      expect(auth.currentUserId, _userB);
      expect(appState.profile?.name, 'Sam Reed');
      expect(appState.profile?.weightKg, 92);

      // 13 and 14. Neither A's name nor A's targets survive the switch.
      expect(appState.profile?.name, isNot('Alex Carter'));
      expect(find.text('Alex Carter'), findsNothing);
      expect(find.text('Sam Reed'), findsOneWidget);
    });

    testWidgets('12, 15. B sees B meals, never A meals', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      auth.existingUserIdOverride = _userB;
      profiles.storedProfile = buildProfile(name: 'Sam Reed');
      // The store now answers with B's meals, as Firestore would once the
      // query is scoped to B's id.
      meals.replaceAll(<SavedMeal>[
        buildSavedMeal(
          id: 'meal-b',
          createdAt: DateTime.now(),
          foodName: 'Sam porridge',
          calories: 300,
        ),
      ]);

      await switchToUserB(tester);

      expect(find.byType(HomeDashboardScreen), findsOneWidget);
      expect(find.text('Sam porridge'), findsOneWidget);
      expect(find.text('Grilled chicken salad'), findsNothing);
    });

    testWidgets('an account with no profile is sent to set one up', (
      WidgetTester tester,
    ) async {
      await beSignedIn(_emailA);
      appState.saveProfile(buildProfile(name: 'Alex Carter'));
      await pumpProfile(tester);

      auth.existingUserIdOverride = _userB;
      // B is a real account that has never filled the form in.
      profiles.storedProfile = null;

      await switchToUserB(tester);

      // A's details must not be waiting there to be saved under B.
      expect(appState.profile, isNull);
      expect(find.byType(HomeDashboardScreen), findsNothing);
      expect(find.text('Alex Carter'), findsNothing);
      // 7. And nothing was written under either account on the way.
      expect(profiles.saveCalls, 0);
      expect(profiles.updateCalls, 0);
    });
  });

  group('regressions', () {
    testWidgets('17, 18. an anonymous user can still upgrade in place', (
      WidgetTester tester,
    ) async {
      await auth.ensureSignedIn();
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      final String? before = auth.currentUserId;

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(find.byType(CreateAccountScreen), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), _emailA);
      await tester.enterText(find.byType(TextFormField).at(1), 'sunflower99');
      await tester.enterText(find.byType(TextFormField).at(2), 'sunflower99');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      // Phase 2G, unchanged: same id, now permanent, data left alone.
      expect(auth.currentUserId, before);
      expect(auth.isAnonymous, isFalse);
      expect(find.text('Account secured'), findsOneWidget);
      expect(find.text(_emailA), findsOneWidget);
      expect(profiles.saveCalls, 0);
      expect(meals.saveCalls, 0);
    });

    testWidgets('17. an anonymous user can still sign in to an account', (
      WidgetTester tester,
    ) async {
      await auth.ensureSignedIn();
      appState.saveProfile(buildProfile());
      await pumpProfile(tester);

      auth.existingUserIdOverride = _userB;
      profiles.storedProfile = buildProfile(name: 'Sam Reed');

      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();

      // This user has a saved profile, so Phase 2J offers to keep it first.
      // Declining that offer must still lead to the ordinary sign-in.
      expect(find.text('Protect your NutriScan data'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Sign in anyway'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), _emailB);
      await tester.enterText(find.byType(TextFormField).at(1), 'bluebird77');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(auth.currentUserId, _userB);
      expect(appState.profile?.name, 'Sam Reed');
    });
  });

  group('22. sign-out is not a data operation', () {
    late FakeFirebaseFirestore firestore;
    late FakeAuthService realAuth;
    late FirestoreProfileRepository realProfiles;
    late FirestoreMealRepository realMeals;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      realAuth = FakeAuthService(userId: _userA);
      realProfiles = FirestoreProfileRepository(
        authService: realAuth,
        firestore: firestore,
      );
      realMeals = FirestoreMealRepository(
        authService: realAuth,
        firestore: firestore,
      );

      await realAuth.ensureSignedIn();
      await realProfiles.saveProfile(buildProfile(name: 'Alex Carter'));
      await realMeals.saveMeal(
        ReviewedMeal.fromAnalysis(buildAnalysis(foodName: 'Chicken salad')),
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

    test('the documents survive untouched, under the same id', () async {
      expect(await docsUnder(_userA, 'profile'), 1);
      expect(await docsUnder(_userA, 'meals'), 1);

      await realAuth.signOut();

      // Nothing removed, nothing moved.
      expect(await docsUnder(_userA, 'profile'), 1);
      expect(await docsUnder(_userA, 'meals'), 1);
      expect(await docsUnder(_userB, 'profile'), 0);
      expect(await docsUnder(_userB, 'meals'), 0);
    });

    test('signing in as somebody else copies nothing across', () async {
      await realAuth.signOut();

      realAuth.existingUserIdOverride = _userB;
      await realAuth.signInWithEmailPassword(
        email: _emailB,
        password: 'bluebird77',
      );

      // B starts empty; A keeps everything.
      expect(await realProfiles.getProfile(), isNull);
      expect(await realMeals.watchMeals().first, isEmpty);
      expect(await docsUnder(_userA, 'profile'), 1);
      expect(await docsUnder(_userA, 'meals'), 1);

      // And a profile saved by B lands under B, leaving A's alone.
      await realProfiles.saveProfile(buildProfile(name: 'Sam Reed'));
      expect(await docsUnder(_userB, 'profile'), 1);
      expect(await docsUnder(_userA, 'profile'), 1);

      final aDoc = await firestore
          .collection('users')
          .doc(_userA)
          .collection('profile')
          .doc('current')
          .get();
      expect(aDoc.data()?['name'], 'Alex Carter');
    });

    test('the account itself is left in place', () async {
      // Sign-out ends a session; it never removes the account, so the same
      // id is reachable again straight afterwards.
      await realAuth.signOut();
      expect(realAuth.currentUserId, isNull);

      final String again = await realAuth.ensureSignedIn();

      expect(again, _userA);
      final UserProfile? profile = await realProfiles.getProfile();
      expect(profile?.name, 'Alex Carter');
    });
  });
}
