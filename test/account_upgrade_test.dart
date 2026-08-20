// Tests for upgrading an anonymous account to a permanent one.
//
// The auth service is faked, so no Firebase or emulator is needed. The point
// of these tests is the surrounding behaviour: validation, what the profile
// screen offers, and that nothing about the user's stored data moves.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/screens/auth/create_account_screen.dart';
import 'package:nutriscan/screens/profile/profile_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/services/auth_service.dart';
import 'package:nutriscan/theme/app_theme.dart';

import 'support/test_doubles.dart';

/// Field order on the create-account form, top to bottom.
const int _emailField = 0;
const int _passwordField = 1;
const int _confirmField = 2;

void main() {
  late AppState appState;
  late FakeAuthService auth;
  late FakeMealRepository meals;
  late FakeProfileRepository profiles;

  setUp(() {
    appState = AppState();
    auth = FakeAuthService(userId: 'uid-abc123');
    meals = FakeMealRepository(
      meals: <SavedMeal>[
        buildSavedMeal(
          id: 'meal-1',
          createdAt: DateTime.now(),
          foodName: 'Chicken salad',
        ),
      ],
    );
    profiles = FakeProfileRepository(storedProfile: buildProfile());
    appState.saveProfile(buildProfile());
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

  Future<void> pumpForm(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(const CreateAccountScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    required String email,
    required String password,
    String? confirm,
  }) async {
    await tester.enterText(find.byType(TextFormField).at(_emailField), email);
    await tester.enterText(
      find.byType(TextFormField).at(_passwordField),
      password,
    );
    await tester.enterText(
      find.byType(TextFormField).at(_confirmField),
      confirm ?? password,
    );
  }

  group('form validation', () {
    testWidgets('7. an invalid email is rejected', (WidgetTester tester) async {
      await pumpForm(tester);
      await fill(tester, email: 'not-an-email', password: 'sunflower99');

      await submit(tester);

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(auth.linkedEmails, isEmpty);
    });

    testWidgets('8. an empty email is rejected', (WidgetTester tester) async {
      await pumpForm(tester);
      await fill(tester, email: '', password: 'sunflower99');

      await submit(tester);

      expect(find.text('Enter your email address'), findsOneWidget);
      expect(auth.linkedEmails, isEmpty);
    });

    testWidgets('9. a password under 8 characters is rejected', (
      WidgetTester tester,
    ) async {
      await pumpForm(tester);
      await fill(tester, email: 'alex@example.com', password: 'short7');

      await submit(tester);

      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(auth.linkedEmails, isEmpty);
    });

    testWidgets('10. mismatched passwords are rejected', (
      WidgetTester tester,
    ) async {
      await pumpForm(tester);
      await fill(
        tester,
        email: 'alex@example.com',
        password: 'sunflower99',
        confirm: 'sunflower98',
      );

      await submit(tester);

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(auth.linkedEmails, isEmpty);
    });

    testWidgets('an empty password is rejected', (WidgetTester tester) async {
      await pumpForm(tester);
      await fill(tester, email: 'alex@example.com', password: '');

      await submit(tester);

      expect(find.text('Enter a password'), findsOneWidget);
      expect(auth.linkedEmails, isEmpty);
    });

    testWidgets('passwords are obscured', (WidgetTester tester) async {
      await pumpForm(tester);

      final List<TextField> fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();

      expect(fields[_emailField].obscureText, isFalse);
      expect(fields[_passwordField].obscureText, isTrue);
      expect(fields[_confirmField].obscureText, isTrue);
    });
  });

  group('linking', () {
    testWidgets('3. a valid email and password links the account', (
      WidgetTester tester,
    ) async {
      await pumpForm(tester);
      await fill(tester, email: 'alex@example.com', password: 'sunflower99');

      await submit(tester);

      expect(auth.linkedEmails, <String>['alex@example.com']);
      expect(auth.isAnonymous, isFalse);
    });

    testWidgets(
      '4, 5, 6 and 17. the account, profile and meals are untouched',
      (WidgetTester tester) async {
        final String uidBefore = auth.currentUserId ?? 'uid-abc123';
        final int mealsBefore = meals.meals.length;
        final bool hadProfile = profiles.storedProfile != null;

        await pumpForm(tester);
        await fill(tester, email: 'alex@example.com', password: 'sunflower99');
        await submit(tester);

        // Same account, same documents: nothing was migrated or rewritten.
        expect(auth.currentUserId, uidBefore);
        expect(meals.meals.length, mealsBefore);
        expect(meals.meals.single.id, 'meal-1');
        expect(meals.deletedIds, isEmpty);
        expect(meals.saveCalls, 0);
        expect(profiles.storedProfile != null, hadProfile);
        expect(profiles.saveCalls, 0);
        expect(profiles.updateCalls, 0);
        expect(appState.profile?.name, 'Alex Carter');
      },
    );

    testWidgets('a failure explains itself and keeps the user on the form', (
      WidgetTester tester,
    ) async {
      auth.linkFailure = const AuthFailure(
        'That email is already used by another account. Try a different one.',
      );
      await pumpForm(tester);
      await fill(tester, email: 'taken@example.com', password: 'sunflower99');

      await submit(tester);

      expect(find.text('Account not created'), findsOneWidget);
      expect(
        find.text(
          'That email is already used by another account. Try a different one.',
        ),
        findsOneWidget,
      );
      expect(find.byType(CreateAccountScreen), findsOneWidget);
      expect(auth.isAnonymous, isTrue);
    });

    testWidgets('the password never reaches app state', (
      WidgetTester tester,
    ) async {
      await pumpForm(tester);
      await fill(tester, email: 'alex@example.com', password: 'sunflower99');
      await submit(tester);

      // The fake records emails only; nothing anywhere holds the password.
      expect(auth.linkedEmails, isNot(contains('sunflower99')));
      expect(appState.profile?.name, isNot(contains('sunflower99')));
      expect(appState.pendingMeal, isNull);
    });
  });

  group('profile account section', () {
    Future<void> pumpProfile(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrap(const ProfileScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('1 and 14. an anonymous user is offered the upgrade', (
      WidgetTester tester,
    ) async {
      await pumpProfile(tester);

      expect(find.text('Create an account'), findsOneWidget);
      expect(
        find.text(
          'Create an account to keep your meals and profile when you change '
          'devices.',
        ),
        findsOneWidget,
      );
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Account secured'), findsNothing);

      // The rest of the profile still works without upgrading.
      expect(find.text('Alex Carter'), findsOneWidget);
      expect(find.text('Your details'), findsOneWidget);
      expect(find.text('Daily targets'), findsOneWidget);
    });

    testWidgets('2, 15 and 16. a permanent user sees only confirmation', (
      WidgetTester tester,
    ) async {
      auth.anonymous = false;

      await pumpProfile(tester);

      expect(find.text('Account secured'), findsOneWidget);
      expect(find.text('Create Account'), findsNothing);
      expect(find.text('Create an account'), findsNothing);
    });

    testWidgets('nothing is offered before anyone is signed in', (
      WidgetTester tester,
    ) async {
      auth.anonymous = null;

      await pumpProfile(tester);

      expect(find.text('Create Account'), findsNothing);
      expect(find.text('Account secured'), findsNothing);
      // The profile itself still renders.
      expect(find.text('Alex Carter'), findsOneWidget);
    });

    testWidgets('upgrading from the profile switches it to secured', (
      WidgetTester tester,
    ) async {
      await pumpProfile(tester);

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(find.byType(CreateAccountScreen), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(_emailField),
        'alex@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).at(_passwordField),
        'sunflower99',
      );
      await tester.enterText(
        find.byType(TextFormField).at(_confirmField),
        'sunflower99',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      // Back on the profile, now showing the upgraded state.
      expect(find.byType(CreateAccountScreen), findsNothing);
      expect(find.text('Account secured'), findsOneWidget);
      expect(find.text('Create Account'), findsNothing);
      expect(auth.linkedEmails, <String>['alex@example.com']);
    });
  });
}
