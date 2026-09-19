import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/firebase_startup.dart';

void main() {
  Widget normalApp() =>
      const MaterialApp(home: Scaffold(body: Text('Normal NutriScan app')));

  testWidgets('successful Firebase initialization starts the normal app', (
    WidgetTester tester,
  ) async {
    int initializationCalls = 0;

    await tester.pumpWidget(
      FirebaseStartup(
        initialize: () async => initializationCalls++,
        readyAppBuilder: normalApp,
      ),
    );
    await tester.pumpAndSettle();

    expect(initializationCalls, 1);
    expect(find.text('Normal NutriScan app'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('failed initialization shows the safe startup error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FirebaseStartup(
        initialize: () async => throw StateError('firebase failed'),
        readyAppBuilder: normalApp,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NutriScan couldn\'t start'), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Normal NutriScan app'), findsNothing);
  });

  testWidgets('Firebase-backed app services are not constructed on failure', (
    WidgetTester tester,
  ) async {
    int serviceGraphConstructions = 0;

    await tester.pumpWidget(
      FirebaseStartup(
        initialize: () async => throw Exception('not initialized'),
        readyAppBuilder: () {
          serviceGraphConstructions++;
          return normalApp();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(serviceGraphConstructions, 0);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('retry can recover and start the normal app', (
    WidgetTester tester,
  ) async {
    int initializationCalls = 0;
    int serviceGraphConstructions = 0;

    await tester.pumpWidget(
      FirebaseStartup(
        initialize: () async {
          initializationCalls++;
          if (initializationCalls == 1) throw Exception('first attempt');
        },
        readyAppBuilder: () {
          serviceGraphConstructions++;
          return normalApp();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(serviceGraphConstructions, 0);
    await tester.tap(find.byKey(const Key('firebase-startup-retry')));
    await tester.pumpAndSettle();

    expect(initializationCalls, 2);
    expect(serviceGraphConstructions, 1);
    expect(find.text('Normal NutriScan app'), findsOneWidget);
  });

  testWidgets('repeated failures remain on the retryable error screen', (
    WidgetTester tester,
  ) async {
    int initializationCalls = 0;
    int serviceGraphConstructions = 0;

    await tester.pumpWidget(
      FirebaseStartup(
        initialize: () async {
          initializationCalls++;
          throw Exception('still unavailable');
        },
        readyAppBuilder: () {
          serviceGraphConstructions++;
          return normalApp();
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('firebase-startup-retry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('firebase-startup-retry')));
    await tester.pumpAndSettle();

    expect(initializationCalls, 3);
    expect(serviceGraphConstructions, 0);
    expect(find.text('NutriScan couldn\'t start'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('raw Firebase failure details are never rendered', (
    WidgetTester tester,
  ) async {
    const String sensitiveDetails =
        'permission-denied apiKey=must-never-be-rendered';
    final List<String> logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };

    try {
      await tester.pumpWidget(
        FirebaseStartup(
          initialize: () async => throw Exception(sensitiveDetails),
          readyAppBuilder: normalApp,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('permission-denied'), findsNothing);
      expect(find.textContaining('apiKey'), findsNothing);
      expect(find.textContaining('must-never-be-rendered'), findsNothing);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      expect(logs.join('\n'), isNot(contains(sensitiveDetails)));
      expect(logs.join('\n'), contains('Firebase startup failed'));
    } finally {
      debugPrint = originalDebugPrint;
    }
  });

  testWidgets('the normal app is not built while initialization is pending', (
    WidgetTester tester,
  ) async {
    final Completer<void> initialization = Completer<void>();
    int serviceGraphConstructions = 0;

    await tester.pumpWidget(
      FirebaseStartup(
        initialize: () => initialization.future,
        readyAppBuilder: () {
          serviceGraphConstructions++;
          return normalApp();
        },
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(serviceGraphConstructions, 0);

    initialization.complete();
    await tester.pumpAndSettle();

    expect(serviceGraphConstructions, 1);
    expect(find.text('Normal NutriScan app'), findsOneWidget);
  });
}
