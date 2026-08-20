// Tests for Phase M2: text-length hardening.
//
// The fault being closed: nothing on the client bounded a profile name, a food
// name or a description, while the security rules bound two of them. An
// over-long value therefore passed the form, reached Firestore and came back
// as `permission-denied`, which the repository words as "You do not have
// access to these meals" - a message about authorisation for what is really a
// length problem, and one the user cannot act on.
//
// These pin the bound at the form and at the model boundary, and pin the two
// properties that make the fix worth having: an invalid value never reaches
// Firestore at all, and the message it produces never mentions permissions.
//
// Lengths are counted in UTF-8 bytes - see TextLimits for why - so the
// boundary cases below use ASCII, where one character is one byte and the
// limit reads the way a user would expect. The multi-byte cases are called
// out separately.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/app/app_scope.dart';
import 'package:nutriscan/app/services_scope.dart';
import 'package:nutriscan/models/food_analysis_result.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/screens/history/history_screen.dart';
import 'package:nutriscan/screens/profile_setup/profile_setup_screen.dart';
import 'package:nutriscan/services/app_state.dart';
import 'package:nutriscan/theme/app_theme.dart';
import 'package:nutriscan/utils/nutrition_validators.dart';
import 'package:nutriscan/utils/text_limits.dart';

import 'support/test_doubles.dart';

/// A string of [length] ASCII characters, which is also [length] UTF-8 bytes.
String ascii(int length) => 'a' * length;

/// A well-formed analysis payload, as the callable would return it.
Map<String, Object?> analysisJson({
  String foodName = 'Grilled chicken salad',
  String description = 'Mixed leaves with sliced grilled chicken breast.',
}) {
  return <String, Object?>{
    'food_name': foodName,
    'description': description,
    'estimated_portion_grams': 320,
    'calories': 580,
    'protein_grams': 42,
    'carbohydrates_grams': 18,
    'fat_grams': 24,
    'fiber_grams': 6,
    'confidence': 0.85,
    'assumptions': <String>['Dressing assumed to be olive oil based.'],
    'items': <Map<String, Object?>>[
      <String, Object?>{'name': 'Chicken breast', 'estimated_portion_grams': 150},
    ],
  };
}

void main() {
  group('1. the limits are the ones the security rules hold', () {
    // Not free choices. If a rule is ever relaxed or tightened, these are the
    // tests that should fail first and send somebody to firestore.rules.
    test('profile name matches isValidProfile: name.size() <= 100', () {
      expect(TextLimits.profileName, 100);
    });

    test('food name matches isNutrition: foodName.size() <= 200', () {
      expect(TextLimits.foodName, 200);
    });

    test('description is the app\'s own bound, and is generous', () {
      // No rule constrains a description, so this one only has to be large
      // enough that no real description meets it.
      expect(TextLimits.description, 1000);
      expect(TextLimits.description, greaterThan(TextLimits.foodName));
    });
  });

  group('2. TextLimits counts UTF-8 bytes, so a value that fits fits the rule',
      () {
    test('ASCII: one character is one byte', () {
      expect(TextLimits.fits(ascii(200), 200), isTrue);
      expect(TextLimits.fits(ascii(201), 200), isFalse);
    });

    test('a multi-byte string is measured by its bytes, not its characters',
        () {
      // 100 CJK characters are 300 UTF-8 bytes. Counting characters would
      // call this a fit and let Firestore refuse it later.
      final String cjk = '食' * 100;
      expect(cjk.length, 100);
      expect(TextLimits.fits(cjk, 200), isFalse);
    });

    test('an astral character counts as its bytes, not its code units', () {
      // One emoji: 2 UTF-16 code units, 4 UTF-8 bytes.
      const String emoji = '\u{1F600}';
      expect(emoji.length, 2);
      expect(TextLimits.fits(emoji, 4), isTrue);
      expect(TextLimits.fits(emoji, 3), isFalse);
    });

    test('the message names a count only when a count would be honest', () {
      // Characters over the limit: the number is meaningful, so it is given.
      expect(
        TextLimits.lengthError(ascii(201), label: 'Food name', maxLength: 200),
        'Food name must be 200 characters or fewer',
      );
      // Characters within the limit but bytes over it: naming 200 would be
      // misleading, so the message just asks for something shorter.
      expect(
        TextLimits.lengthError('食' * 100,
            label: 'Food name', maxLength: 200),
        'Food name is too long. Please shorten it.',
      );
    });
  });

  group('3. food name validation', () {
    test('a normal name is accepted', () {
      expect(NutritionValidators.foodName('Grilled chicken salad'), isNull);
    });

    test('empty is rejected with the wording it always had', () {
      // Unchanged on purpose: two existing tests assert this exact string.
      expect(NutritionValidators.foodName(''), 'Enter a food name');
      expect(NutritionValidators.foodName(null), 'Enter a food name');
    });

    test('whitespace-only is rejected as empty, not as too long', () {
      expect(NutritionValidators.foodName('     '), 'Enter a food name');
      expect(NutritionValidators.foodName('\n\t  '), 'Enter a food name');
    });

    test('exactly the maximum is accepted', () {
      expect(NutritionValidators.foodName(ascii(200)), isNull);
    });

    test('one character over the maximum is rejected', () {
      expect(
        NutritionValidators.foodName(ascii(201)),
        'Food name must be 200 characters or fewer',
      );
    });

    test('a very large input is rejected rather than hanging or throwing', () {
      expect(NutritionValidators.foodName(ascii(100000)), isNotNull);
    });

    test('surrounding whitespace is trimmed before measuring', () {
      // What gets stored is the trimmed value, so that is what is judged: a
      // name at the limit must not be failed by the spaces around it.
      expect(NutritionValidators.foodName('   ${ascii(200)}   '), isNull);
      expect(NutritionValidators.foodName('  ${ascii(201)}  '), isNotNull);
    });

    test('the message never mentions permissions or access', () {
      final String message = NutritionValidators.foodName(ascii(400))!;
      expect(message.toLowerCase(), isNot(contains('permission')));
      expect(message.toLowerCase(), isNot(contains('access')));
    });
  });

  group('4. description validation', () {
    test('a valid description is accepted', () {
      expect(
        NutritionValidators.description('Mixed leaves with grilled chicken.'),
        isNull,
      );
    });

    test('an empty description is allowed - the field is optional', () {
      expect(NutritionValidators.description(''), isNull);
      expect(NutritionValidators.description(null), isNull);
      expect(NutritionValidators.description('   '), isNull);
    });

    test('exactly the maximum is accepted', () {
      expect(NutritionValidators.description(ascii(1000)), isNull);
    });

    test('one character over the maximum is rejected', () {
      expect(
        NutritionValidators.description(ascii(1001)),
        'Description must be 1000 characters or fewer',
      );
    });

    test('a very large description is rejected', () {
      expect(NutritionValidators.description(ascii(50000)), isNotNull);
    });
  });

  group('5. model-generated text is bounded at the parse boundary', () {
    test('a normal analysis parses as it always did', () {
      final FoodAnalysisResult result =
          FoodAnalysisResult.fromJson(analysisJson());

      expect(result.foodName, 'Grilled chicken salad');
      expect(result.calories, 580);
      expect(result.items, hasLength(1));
    });

    test('a name at exactly the maximum is accepted', () {
      final FoodAnalysisResult result = FoodAnalysisResult.fromJson(
        analysisJson(foodName: ascii(200)),
      );
      expect(result.foodName, ascii(200));
    });

    test('an oversized model name is refused, not silently truncated', () {
      // Truncating would quietly change what the model said. Refusing keeps
      // the app honest about the estimate it is showing.
      expect(
        () => FoodAnalysisResult.fromJson(analysisJson(foodName: ascii(201))),
        throwsFormatException,
      );
    });

    test('an enormous model name is refused', () {
      expect(
        () => FoodAnalysisResult.fromJson(analysisJson(foodName: ascii(20000))),
        throwsFormatException,
      );
    });

    test('an oversized model description is refused', () {
      expect(
        () => FoodAnalysisResult.fromJson(
          analysisJson(description: ascii(1001)),
        ),
        throwsFormatException,
      );
    });

    test('model text is trimmed, so padding cannot push it over the limit', () {
      final FoodAnalysisResult result = FoodAnalysisResult.fromJson(
        analysisJson(foodName: '  Grilled chicken salad  '),
      );
      expect(result.foodName, 'Grilled chicken salad');
    });

    test('a rejected analysis fails as a format problem, which the scan '
        'screen already turns into a plain retryable message', () {
      // FoodAnalysisService catches FormatException and answers with
      // FoodAnalysisFailure('The analysis came back in an unexpected
      // format...'). No Gemini or Firebase wording reaches the user.
      try {
        FoodAnalysisResult.fromJson(analysisJson(foodName: ascii(5000)));
        fail('an oversized name should not parse');
      } on FormatException catch (error) {
        expect(error, isA<FormatException>());
        final String text = error.toString().toLowerCase();
        expect(text, isNot(contains('permission')));
        expect(text, isNot(contains('gemini')));
        expect(text, isNot(contains('firebase')));
      }
    });
  });

  group('6. an invalid value never reaches Firestore', () {
    late FakeMealRepository repository;
    late FakeProfileRepository profiles;
    late FakeAuthService auth;
    late AppState appState;

    setUp(() {
      repository = FakeMealRepository(
        meals: <SavedMeal>[
          buildSavedMeal(id: 'meal-1', createdAt: DateTime.now()),
        ],
      );
      profiles = FakeProfileRepository();
      auth = FakeAuthService()..beginSession();
      appState = AppState();
    });

    tearDown(() {
      repository.dispose();
      profiles.dispose();
      appState.dispose();
    });

    Future<void> pump(WidgetTester tester, Widget child) async {
      // Tall surface: the edit form is longer than a default test viewport,
      // and its save button sits at the bottom.
      await tester.binding.setSurfaceSize(const Size(500, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ServicesScope(
          authService: auth,
          mealRepository: repository,
          profileRepository: profiles,
          child: AppScope(
            state: appState,
            child: MaterialApp(
              theme: AppTheme.light,
              onGenerateRoute: AppRoutes.onGenerateRoute,
              home: child,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Opens the editor the way a user does, so it is a pushed route and can
    /// pop back to History on success.
    Future<void> openEditor(WidgetTester tester) async {
      await pump(tester, const HistoryScreen());
      await tester.tap(find.byTooltip('Meal actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
    }

    testWidgets('an over-long food name blocks the write and says why',
        (WidgetTester tester) async {
      await openEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Grilled chicken salad'),
        ascii(201),
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, 0, reason: 'Firestore was still called');
      expect(
        find.text('Food name must be 200 characters or fewer'),
        findsOneWidget,
      );
      // The message this whole phase exists to stop showing.
      expect(find.textContaining('do not have access'), findsNothing);
      expect(find.textContaining('permission'), findsNothing);
    });

    testWidgets('an over-long description blocks the write',
        (WidgetTester tester) async {
      await openEditor(tester);

      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Mixed leaves with sliced grilled chicken breast.',
        ),
        ascii(1001),
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, 0);
      expect(
        find.text('Description must be 1000 characters or fewer'),
        findsOneWidget,
      );
    });

    testWidgets('a valid edit still saves exactly as before',
        (WidgetTester tester) async {
      await openEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Grilled chicken salad'),
        'Chicken salad',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, 1);
      expect(repository.updatedMeals.single.current.foodName, 'Chicken salad');
    });

    testWidgets('a name at exactly the limit still saves',
        (WidgetTester tester) async {
      await openEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Grilled chicken salad'),
        ascii(200),
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, 1);
      expect(repository.updatedMeals.single.current.foodName, ascii(200));
    });

    testWidgets('an over-long profile name blocks the write and says why',
        (WidgetTester tester) async {
      await pump(tester, const ProfileSetupScreen());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Alex Carter'),
        ascii(101),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. 28'),
        '28',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '175'), '175');
      await tester.enterText(find.widgetWithText(TextFormField, '70'), '70');

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(profiles.saveCalls, 0, reason: 'Firestore was still called');
      expect(
        find.text('Name must be 100 characters or fewer'),
        findsOneWidget,
      );
      expect(find.textContaining('do not have access'), findsNothing);
    });

    testWidgets('a profile name at exactly the limit saves normally',
        (WidgetTester tester) async {
      await pump(tester, const ProfileSetupScreen());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Alex Carter'),
        ascii(100),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. 28'),
        '28',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '175'), '175');
      await tester.enterText(find.widgetWithText(TextFormField, '70'), '70');

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(profiles.saveCalls, 1);
      expect(profiles.storedProfile!.name, ascii(100));
    });

    testWidgets('a whitespace-only profile name is still rejected as empty',
        (WidgetTester tester) async {
      await pump(tester, const ProfileSetupScreen());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Alex Carter'),
        '    ',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(profiles.saveCalls, 0);
      expect(find.text('Please enter your name'), findsOneWidget);
    });
  });

  group('7. stored documents stay readable', () {
    // The bound belongs on the way in. Applying it on the way out would make
    // an already-stored document unreadable, which would lose somebody's
    // history to a validation rule added afterwards.
    test('a meal with an over-long stored name still reads back', () {
      final SavedMeal? meal = mealFromDocument('meal-1', <String, Object?>{
        MealFields.userId: 'user-a',
        MealFields.foodName: ascii(5000),
        MealFields.isEdited: false,
        MealFields.createdAt: DateTime(2026, 8, 20, 12),
        MealFields.current: <String, Object?>{
          MealFields.foodName: ascii(5000),
          MealFields.calories: 400,
        },
        MealFields.aiEstimate: <String, Object?>{
          MealFields.foodName: ascii(5000),
          MealFields.calories: 400,
        },
      });

      expect(meal, isNotNull);
      expect(meal!.current.foodName, hasLength(5000));
      expect(meal.current.calories, 400);
    });

    test('a meal with an over-long stored description still reads back', () {
      final SavedMeal? meal = mealFromDocument('meal-2', <String, Object?>{
        MealFields.userId: 'user-a',
        MealFields.foodName: 'Meal',
        MealFields.isEdited: false,
        MealFields.createdAt: DateTime(2026, 8, 20, 12),
        MealFields.current: <String, Object?>{
          MealFields.foodName: 'Meal',
          MealFields.description: ascii(9000),
          MealFields.calories: 400,
        },
        MealFields.aiEstimate: <String, Object?>{
          MealFields.foodName: 'Meal',
          MealFields.calories: 400,
        },
      });

      expect(meal, isNotNull);
      expect(meal!.current.description, hasLength(9000));
    });
  });
}
