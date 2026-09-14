import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nutriscan/models/food_analysis_result.dart';
import 'package:nutriscan/services/food_analysis_service.dart';

const String _successBody = '''
{
  "status": "ok",
  "analysis": {
    "food_name": "Rice bowl",
    "description": "Rice with vegetables.",
    "estimated_portion_grams": 350,
    "calories": 510,
    "protein_grams": 18,
    "carbohydrates_grams": 82,
    "fat_grams": 12,
    "fiber_grams": 7,
    "confidence": 0.8,
    "assumptions": ["The sauce is lightly sweetened."],
    "items": [{"name": "Rice", "estimated_portion_grams": 220}]
  }
}
''';

class _FakeUser implements User {
  _FakeUser(this.token);

  final String? token;

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => token;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements FirebaseAuth {
  _FakeAuth(this.user);

  final User? user;

  @override
  User? get currentUser => user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late File image;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('nutriscan_analysis');
    image = File('${directory.path}/meal.jpg');
    await image.writeAsBytes(<int>[1, 2, 3]);
  });

  tearDownAll(() => directory.delete(recursive: true));

  FoodAnalysisService service(http.Client client, {User? user}) {
    return FoodAnalysisService(
      auth: _FakeAuth(user ?? _FakeUser('firebase-id-token')),
      client: client,
      endpoint: Uri.parse('https://api.example.test/api/analyze-food'),
      timeout: const Duration(milliseconds: 20),
    );
  }

  test('successful request sends auth and parses nutrition', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.headers['authorization'], 'Bearer firebase-id-token');
      expect(request.headers['content-type'], startsWith('application/json'));
      expect(request.body, contains('"mimeType":"image/jpeg"'));
      return http.Response(_successBody, 200);
    });

    final FoodAnalysisOutcome outcome = await service(client).analyze(image);

    expect(outcome, isA<FoodAnalysisSuccess>());
    final FoodAnalysisResult result = (outcome as FoodAnalysisSuccess).result;
    expect(result.foodName, 'Rice bowl');
    expect(result.calories, 510);
  });

  test('missing Firebase token is rejected without an HTTP request', () async {
    int calls = 0;
    final MockClient client = MockClient((_) async {
      calls++;
      return http.Response(_successBody, 200);
    });

    final FoodAnalysisOutcome outcome = await service(
      client,
      user: _FakeUser(null),
    ).analyze(image);

    expect(outcome, isA<FoodAnalysisFailure>());
    expect(calls, 0);
  });

  test('image over 3 MiB is rejected before an HTTP request', () async {
    final File oversized = File('${directory.path}/oversized.jpg');
    await oversized.writeAsBytes(
      List<int>.filled(maxFoodAnalysisImageBytes + 1, 0),
    );
    int calls = 0;
    final MockClient client = MockClient((_) async {
      calls++;
      return http.Response(_successBody, 200);
    });

    final FoodAnalysisOutcome outcome = await service(client)
        .analyze(oversized);

    expect(outcome, isA<FoodAnalysisFailure>());
    expect(
      (outcome as FoodAnalysisFailure).message,
      'That photo is too large. Choose a smaller image and try again.',
    );
    expect(calls, 0);
  });

  test('image at 3 MiB stays below 4.5 MiB after JSON encoding', () async {
    final File atLimit = File('${directory.path}/at-limit.jpg');
    await atLimit.writeAsBytes(List<int>.filled(maxFoodAnalysisImageBytes, 0));
    int? requestBytes;
    final MockClient client = MockClient((http.Request request) async {
      requestBytes = request.bodyBytes.length;
      return http.Response(_successBody, 200);
    });

    final FoodAnalysisOutcome outcome = await service(client).analyze(atLimit);

    expect(outcome, isA<FoodAnalysisSuccess>());
    expect(requestBytes, isNotNull);
    expect(requestBytes!, lessThan(4.5 * 1024 * 1024));
  });

  test('401, 413 and 429 responses use safe messages', () async {
    for (final ({int status, String code, String expected}) sample
        in <({int status, String code, String expected})>[
          (
            status: 401,
            code: 'unauthenticated',
            expected: 'The app is not allowed to run an analysis right now.',
          ),
          (
            status: 429,
            code: 'rate_limited',
            expected:
                'You have reached the scan limit. Please try again later.',
          ),
          (
            status: 413,
            code: 'image_too_large',
            expected: 'That photo is too large. Choose a smaller image and try again.',
          ),
        ]) {
      final MockClient client = MockClient(
        (_) async => http.Response(
          '{"error":{"code":"${sample.code}","message":"hidden"}}',
          sample.status,
        ),
      );

      final FoodAnalysisOutcome outcome = await service(client).analyze(image);
      expect((outcome as FoodAnalysisFailure).message, sample.expected);
    }
  });

  test('backend 5xx does not expose its body', () async {
    final MockClient client = MockClient(
      (_) async => http.Response('internal stack and secret', 500),
    );

    final FoodAnalysisOutcome outcome = await service(client).analyze(image);

    expect(
      (outcome as FoodAnalysisFailure).message,
      'The photo could not be analysed. Please try again.',
    );
  });

  test('malformed success response is rejected', () async {
    final MockClient client = MockClient(
      (_) async => http.Response('{"status":"ok","analysis":{}}', 200),
    );

    final FoodAnalysisOutcome outcome = await service(client).analyze(image);

    expect(
      (outcome as FoodAnalysisFailure).message,
      'The analysis came back in an unexpected format. Please try again.',
    );
  });

  test('timeout and network failure are handled', () async {
    final MockClient timeoutClient = MockClient(
      (_) => Completer<http.Response>().future,
    );
    final MockClient networkClient = MockClient(
      (_) async => throw http.ClientException('connection reset'),
    );

    final FoodAnalysisOutcome timeout = await service(timeoutClient)
        .analyze(image);
    final FoodAnalysisOutcome network = await service(networkClient)
        .analyze(image);

    expect(
      (timeout as FoodAnalysisFailure).message,
      'The analysis took too long. Please try again.',
    );
    expect(
      (network as FoodAnalysisFailure).message,
      'No internet connection. Connect and try again.',
    );
  });
}
