// Tests for signing back in to an existing account, and password reset.
//
// The auth service is faked so no Firebase or emulator is needed. Where the
// point is that recovering an account reaches the data already stored under
// its id, the real Firestore repositories run against an in-memory database.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/nutriscan_app.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/models/user_profile.dart';
import 'package:nutriscan/screens/auth/reset_password_screen.dart';
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

/// Field order on the sign-in form, top to bottom.
const int _emailField = 0;
const int _passwordField = 1;

/// The account that already exists, as Phase 2G would have left it.
const String _existingUserId = 'uid-from-phase-2g';
const String _existingEmail = 'alex.carter@example.com';
const String _password = 'sunflower99';

void main() {
  late AppState appState;
  late FakeAuthService auth;
  late FakeMealRepository meals;
  late FakeProfileRepository profiles;

  setUp(() {
    appState = AppState();
    auth = FakeAuthService(
      userId: 'uid-on-this-device',
      existingUserId: _existingUserId,
    );
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

  Future<void> pumpSignIn(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(const SignInScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    required String email,
    required String password,
  }) async {
    await tester.enterText(find.byType(TextFormField).at(_emailField), email);
    await tester.enterText(
      find.byType(TextFormField).at(_passwordField),
      password,
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  group('form validation', () {
    testWidgets('1. an empty email is rejected', (WidgetTester tester) async {
      await pumpSignIn(tester);
      await fill(tester, email: '', password: _password);

      await submit(tester);

      expect(find.text('Enter your email address'), findsOneWidget);
      expect(auth.signedInEmails, isEmpty);
    });

    testWidgets('2. an invalid email is rejected', (WidgetTester tester) async {
      await pumpSignIn(tester);
      await fill(tester, email: 'not-an-email', password: _password);

      await submit(tester);

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(auth.signedInEmails, isEmpty);
    });

    testWidgets('3. an empty password is rejected', (
      WidgetTester tester,
    ) async {
      await pumpSignIn(tester);
      await fill(tester, email: _existingEmail, password: '');

      await submit(tester);

      expect(find.text('Enter your password'), findsOneWidget);
      expect(auth.signedInEmails, isEmpty);
    });

    testWidgets('the password is obscured and the email is not', (
      WidgetTester tester,
    ) async {
      await pumpSignIn(tester);

      final List<TextField> fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();

      expect(fields[_emailField].obscureText, isFalse);
      expect(fields[_passwordField].obscureText, isTrue);
    });
  });

  group('signing in', () {
    testWidgets('4 and 7. a valid sign-in leaves a permanent session', (
      WidgetTester tester,
    ) async {
      await pumpSignIn(tester);
      await fill(tester, email: _existingEmail, password: _password);

      await submit(tester);

      expect(auth.signedInEmails, <String>[_existingEmail]);
      expect(auth.isAnonymous, isFalse);
      // The dashboard replaces the whole stack, so the form is gone.
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.byType(HomeDashboardScreen), findsOneWidget);
    });

    testWidgets('8. the account keeps the id it already had', (
      WidgetTester tester,
    ) async {
      await pumpSignIn(tester);
      await fill(tester, email: _existingEmail, password: _password);

      await submit(tester);

      // Not the id this device was using: the existing account's own.
      expect(auth.currentUserId, _existingUserId);
    });

    testWidgets('5. invalid credentials keep the user on the form', (
      WidgetTester tester,
    ) async {
      auth.signInFailure = const AuthFailure(
        'That email or password is not right. Please try again.',
      );

      await pumpSignIn(tester);
      await fill(tester, email: _existingEmail, password: 'wrong-password');
      await submit(tester);

      expect(find.text('Not signed in'), findsOneWidget);
      expect(
        find.text('That email or password is not right. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(HomeDashboardScreen), findsNothing);
    });

    testWidgets('6. nothing Firebase-shaped reaches the screen', (
      WidgetTester tester,
    ) async {
      auth.signInFailure = const AuthFailure(
        'That email or password is not right. Please try again.',
      );

      await pumpSignIn(tester);
      await fill(tester, email: _existingEmail, password: 'wrong-password');
      await submit(tester);

      final Iterable<Text> shown = tester.widgetList<Text>(find.byType(Text));
      for (final Text widget in shown) {
        final String label = widget.data ?? '';
        expect(label, isNot(contains('FirebaseAuthException')));
        expect(label, isNot(contains('firebase')));
        expect(label, isNot(contains('wrong-password')));
        expect(label, isNot(contains('invalid-credential')));
        // Nor the password itself, anywhere on screen.
        expect(label, isNot(contains('wrong-password')));
      }
    });

    testWidgets('a failed attempt can be retried', (WidgetTester tester) async {
      auth.signInFailure = const AuthFailure(
        'That email or password is not right. Please try again.',
      );

      await pumpSignIn(tester);
      await fill(tester, email: _existingEmail, password: 'wrong-password');
      await submit(tester);

      auth.signInFailure = null;
      await fill(tester, email: _existingEmail, password: _password);
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeDashboardScreen), findsOneWidget);
      expect(auth.signedInEmails, <String>[_existingEmail]);
    });

    testWidgets('an account with no profile is sent to set one up', (
      WidgetTester tester,
    ) async {
      profiles.storedProfile = null;
      appState.saveProfile(buildProfile(name: 'Previous Session'));

      await pumpSignIn(tester);
      await fill(tester, email: _existingEmail, password: _password);
      await submit(tester);

      // The previous session's details must not follow the user across.
      expect(appState.profile, isNull);
      expect(find.byType(HomeDashboardScreen), findsNothing);
    });
  });

  group('the password is never kept', () {
    testWidgets('14. it never reaches app state', (WidgetTester tester) async {
      await pumpSignIn(tester);
      await fill(tester, email: _existingEmail, password: _password);
      await submit(tester);

      expect(appState.profile?.name, isNot(contains(_password)));
      expect(appState.pendingMeal, isNull);
    });

    testWidgets('15. nothing the app stores has it either', (
      WidgetTester tester,
    ) async {
      await pumpSignIn(tester);
      await fill(tester, email: _existingEmail, password: _password);
      await submit(tester);

      // The auth double records emails only; the repositories were not asked
      // to write anything at all during sign-in.
      expect(auth.signedInEmails, isNot(contains(_password)));
      expect(auth.linkedEmails, isEmpty);
      expect(profiles.saveCalls, 0);
      expect(profiles.updateCalls, 0);
      expect(meals.saveCalls, 0);
      expect(meals.deletedIds, isEmpty);
    });
  });

  group('password reset', () {
    Future<void> pumpReset(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrap(const ResetPasswordScreen()));
      await tester.pumpAndSettle();
    }

    Future<void> send(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Send reset email'));
      await tester.pumpAndSettle();
    }

    testWidgets('11. an empty or invalid email is rejected', (
      WidgetTester tester,
    ) async {
      await pumpReset(tester);

      await send(tester);
      expect(find.text('Enter your email address'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
      await send(tester);
      expect(find.text('Enter a valid email address'), findsOneWidget);

      expect(auth.resetEmails, isEmpty);
    });

    testWidgets('12. a sent email is confirmed without naming the account', (
      WidgetTester tester,
    ) async {
      await pumpReset(tester);
      await tester.enterText(find.byType(TextFormField).first, _existingEmail);

      await send(tester);

      expect(auth.resetEmails, <String>[_existingEmail]);
      expect(find.text('Check your inbox'), findsOneWidget);
      // Worded so it cannot confirm whether the address has an account.
      expect(
        find.textContaining('If that address has a NutriScan account'),
        findsOneWidget,
      );
      expect(find.text('Back to sign in'), findsOneWidget);
    });

    testWidgets('13. a failure is explained safely', (
      WidgetTester tester,
    ) async {
      auth.resetFailure = const AuthFailure(
        'Too many attempts. Please wait a moment and try again.',
      );

      await pumpReset(tester);
      await tester.enterText(find.byType(TextFormField).first, _existingEmail);
      await send(tester);

      expect(find.text('Email not sent'), findsOneWidget);
      expect(
        find.text('Too many attempts. Please wait a moment and try again.'),
        findsOneWidget,
      );
      expect(find.text('Check your inbox'), findsNothing);

      final Iterable<Text> shown = tester.widgetList<Text>(find.byType(Text));
      for (final Text widget in shown) {
        expect(widget.data ?? '', isNot(contains('FirebaseAuthException')));
      }
    });

    testWidgets('reset opens from the sign-in form with the email filled in', (
      WidgetTester tester,
    ) async {
      await pumpSignIn(tester);
      await tester.enterText(
        find.byType(TextFormField).at(_emailField),
        _existingEmail,
      );

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.text(_existingEmail), findsOneWidget);
    });
  });

  group('entry points', () {
    testWidgets('an anonymous user is offered both upgrade and sign-in', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(500, 2800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      appState.saveProfile(buildProfile());

      await tester.pumpWidget(wrap(const ProfileScreen()));
      await tester.pumpAndSettle();

      // 25 and Phase 2G: the upgrade offer is untouched.
      expect(find.text('Create an account'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Already have an account? Sign in'), findsOneWidget);
      expect(find.text('Account secured'), findsNothing);
    });

    testWidgets('25. a permanent user sees neither offer', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(500, 2800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      auth.anonymous = false;
      appState.saveProfile(buildProfile());

      await tester.pumpWidget(wrap(const ProfileScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Account secured'), findsOneWidget);
      expect(find.text('Create Account'), findsNothing);
      expect(find.text('Create an account'), findsNothing);
      expect(find.text('Already have an account? Sign in'), findsNothing);
    });

    testWidgets('onboarding offers sign-in without disturbing itself', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      // 18. Onboarding still works exactly as it did.
      expect(find.text('Scan any meal'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);
    });
  });

  group('startup', () {
    late FakeMealRepository startupMeals;
    late FakeProfileRepository startupProfiles;

    setUp(() {
      startupMeals = FakeMealRepository();
      startupProfiles = FakeProfileRepository();
    });

    tearDown(() {
      startupMeals.dispose();
      startupProfiles.dispose();
    });

    Widget buildApp(FakeAuthService service) {
      return NutriScanApp(
        authService: service,
        mealRepository: startupMeals,
        profileRepository: startupProfiles,
      );
    }

    testWidgets('no session means no account is created behind the user', (
      WidgetTester tester,
    ) async {
      final FakeAuthService fresh = FakeAuthService();

      await tester.pumpWidget(buildApp(fresh));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Launching must not sign anyone in: that would rule out recovering an
      // account before the user has had the chance to ask for it.
      expect(fresh.signInCalls, 0);
      expect(fresh.currentUserId, isNull);
      expect(startupProfiles.loadCalls, 0);
    });

    testWidgets('18. a first-time user still lands on onboarding', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildApp(FakeAuthService()));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Scan any meal'), findsOneWidget);
      expect(find.text('Already have an account? Sign in'), findsOneWidget);
    });

    testWidgets('a returning user goes straight to their dashboard', (
      WidgetTester tester,
    ) async {
      final FakeAuthService returning = FakeAuthService();
      // A session already exists, as it would after a restart.
      await returning.ensureSignedIn();
      startupProfiles.storedProfile = buildProfile();

      await tester.pumpWidget(buildApp(returning));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(HomeDashboardScreen), findsOneWidget);
      expect(startupProfiles.loadCalls, greaterThan(0));
    });

    testWidgets('a returning anonymous user with no profile onboards', (
      WidgetTester tester,
    ) async {
      final FakeAuthService returning = FakeAuthService();
      await returning.ensureSignedIn();

      await tester.pumpWidget(buildApp(returning));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
    });
  });

  group('recovering the data stored under an account', () {
    late FakeFirebaseFirestore firestore;
    late FakeAuthService recovering;
    late FirestoreProfileRepository realProfiles;
    late FirestoreMealRepository realMeals;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      recovering = FakeAuthService(
        userId: 'uid-on-this-device',
        existingUserId: _existingUserId,
      );
      realProfiles = FirestoreProfileRepository(
        authService: recovering,
        firestore: firestore,
      );
      realMeals = FirestoreMealRepository(
        authService: recovering,
        firestore: firestore,
      );

      // What Phase 2G left behind, written straight to the database under the
      // account's own id.
      await firestore
          .collection('users')
          .doc(_existingUserId)
          .collection('profile')
          .doc('current')
          .set(<String, Object?>{
            'uid': _existingUserId,
            'name': 'Alex Carter',
            'age': 28,
            'gender': 'male',
            'heightCm': 175.0,
            'weightKg': 55.0,
            'activityLevel': 'moderate',
            'goal': 'maintain',
          });

      await firestore
          .collection('users')
          .doc(_existingUserId)
          .collection('meals')
          .doc('meal-from-2g')
          .set(<String, Object?>{
            MealFields.userId: _existingUserId,
            MealFields.foodName: 'Grilled chicken salad',
            MealFields.isEdited: false,
            MealFields.createdAt: DateTime.now(),
            MealFields.current: <String, Object?>{
              MealFields.foodName: 'Grilled chicken salad',
              MealFields.calories: 465,
              MealFields.protein: 42,
              MealFields.carbs: 18,
              MealFields.fat: 24,
            },
            MealFields.aiEstimate: <String, Object?>{
              MealFields.foodName: 'Grilled chicken salad',
              MealFields.calories: 465,
            },
          });
    });

    test('9 and 10. the profile and meals are simply there again', () async {
      // Before signing in this device is on its own anonymous id and sees
      // nothing.
      expect(await realProfiles.getProfile(), isNull);
      expect(await realMeals.watchMeals().first, isEmpty);

      await recovering.signInWithEmailPassword(
        email: _existingEmail,
        password: _password,
      );

      expect(recovering.currentUserId, _existingUserId);

      final UserProfile? profile = await realProfiles.getProfile();
      expect(profile, isNotNull);
      expect(profile!.name, 'Alex Carter');
      expect(profile.weightKg, 55.0);

      final List<SavedMeal> found = await realMeals.watchMeals().first;
      expect(found, hasLength(1));
      expect(found.single.id, 'meal-from-2g');
      expect(found.single.current.foodName, 'Grilled chicken salad');
    });

    test('16 and 17. nothing is copied, moved, or rewritten', () async {
      await recovering.signInWithEmailPassword(
        email: _existingEmail,
        password: _password,
      );
      await realProfiles.getProfile();
      await realMeals.watchMeals().first;

      // The documents are still where Phase 2G put them, and the id this
      // device used before has nothing under it.
      final profileDoc = await firestore
          .collection('users')
          .doc(_existingUserId)
          .collection('profile')
          .doc('current')
          .get();
      expect(profileDoc.exists, isTrue);

      final mealDocs = await firestore
          .collection('users')
          .doc(_existingUserId)
          .collection('meals')
          .get();
      expect(mealDocs.docs, hasLength(1));
      expect(mealDocs.docs.single.id, 'meal-from-2g');

      final strayProfile = await firestore
          .collection('users')
          .doc('uid-on-this-device')
          .collection('profile')
          .get();
      final strayMeals = await firestore
          .collection('users')
          .doc('uid-on-this-device')
          .collection('meals')
          .get();
      expect(strayProfile.docs, isEmpty);
      expect(strayMeals.docs, isEmpty);
    });

    test('the anonymous session starts when the app first needs one', () async {
      // Nothing has claimed an account yet, as at launch.
      expect(recovering.currentUserId, isNull);

      // Saving a profile is the first thing that needs a user id, and the
      // repository asks for one then - not before.
      await realProfiles.saveProfile(buildProfile(name: 'New User'));

      expect(recovering.currentUserId, 'uid-on-this-device');
      final saved = await firestore
          .collection('users')
          .doc('uid-on-this-device')
          .collection('profile')
          .doc('current')
          .get();
      expect(saved.exists, isTrue);
    });

    test('the dashboard total is the account own meals', () async {
      await recovering.signInWithEmailPassword(
        email: _existingEmail,
        password: _password,
      );

      final List<SavedMeal> found = await realMeals.watchMeals().first;

      expect(totalsFor(found).calories, 465);
    });
  });
}
