// Basic smoke tests for the whole app.
//
// They check that it starts on the splash screen and then moves on to
// onboarding for a user who has not set up a profile yet. The services are
// faked, so no Firebase project or emulator is needed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/nutriscan_app.dart';

import 'support/test_doubles.dart';

void main() {
  late FakeMealRepository mealRepository;
  late FakeProfileRepository profileRepository;

  setUp(() {
    mealRepository = FakeMealRepository();
    profileRepository = FakeProfileRepository();
  });

  tearDown(() {
    mealRepository.dispose();
    profileRepository.dispose();
  });

  Widget buildApp() {
    return NutriScanApp(
      authService: FakeAuthService(),
      mealRepository: mealRepository,
      profileRepository: profileRepository,
    );
  }

  testWidgets('Splash screen shows the app name', (WidgetTester tester) async {
    await tester.pumpWidget(buildApp());

    expect(find.text('NutriScan'), findsOneWidget);

    // Let the splash finish so its timer does not outlive the test.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('A new user is taken to onboarding after the splash', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildApp());

    // Let the 2 second splash timer fire, then finish the page transition.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Scan any meal'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('the app does not claim an account before the user does', (
    WidgetTester tester,
  ) async {
    // Launching used to sign in anonymously straight away. It no longer does:
    // an account created here would belong to this device before the user has
    // had the chance to sign in to one they already have. The anonymous
    // session is started when the app first needs it - saving a profile.
    final FakeAuthService auth = FakeAuthService();

    await tester.pumpWidget(
      NutriScanApp(
        authService: auth,
        mealRepository: mealRepository,
        profileRepository: profileRepository,
      ),
    );
    await tester.pump();

    expect(auth.signInCalls, 0);
    expect(auth.currentUserId, isNull);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Still nothing after the splash has handed over to onboarding.
    expect(auth.signInCalls, 0);
  });
}
