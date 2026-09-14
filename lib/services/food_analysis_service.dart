import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/food_analysis_result.dart';

/// A 3 MiB image expands to 4 MiB in base64, leaving room for the JSON
/// envelope below Vercel's 4.5 MB request-body limit.
const int maxFoodAnalysisImageBytes = 3 * 1024 * 1024;

const String _imageTooLargeMessage =
    'That photo is too large. Choose a smaller image and try again.';

/// Result of one analysis attempt.
///
/// A sealed class so every screen has to handle all three outcomes - there is
/// no way to forget the failure path.
sealed class FoodAnalysisOutcome {
  const FoodAnalysisOutcome();
}

/// The photo showed food and the model returned an estimate.
class FoodAnalysisSuccess extends FoodAnalysisOutcome {
  const FoodAnalysisSuccess(this.result);

  final FoodAnalysisResult result;
}

/// The photo was readable but had no food in it. Not an error.
class FoodAnalysisNoFood extends FoodAnalysisOutcome {
  const FoodAnalysisNoFood(this.reason);

  final String reason;
}

/// Something went wrong. [message] is safe to show to the user.
class FoodAnalysisFailure extends FoodAnalysisOutcome {
  const FoodAnalysisFailure(this.message);

  final String message;
}

/// Sends a food photo to NutriScan's authenticated analysis API.
///
/// The app never talks to Gemini directly and never holds an AI API key: the
/// photo goes to the Vercel backend, which keeps the key server-side.
class FoodAnalysisService {
  FoodAnalysisService({
    FirebaseAuth? auth,
    http.Client? client,
    Uri? endpoint,
    Duration timeout = const Duration(seconds: 70),
  }) : this._(
         auth: auth ?? FirebaseAuth.instance,
         client: client ?? http.Client(),
         endpoint: endpoint,
         timeout: timeout,
       );

  FoodAnalysisService._({
    required this._auth,
    required this._client,
    required this._endpoint,
    required this._timeout,
  });

  final FirebaseAuth _auth;
  final http.Client _client;
  final Uri? _endpoint;
  final Duration _timeout;

  /// Analyses [image] and never throws - failures come back as
  /// [FoodAnalysisFailure].
  Future<FoodAnalysisOutcome> analyze(File image) async {
    try {
      final User? user = _auth.currentUser;
      final String? idToken = await user?.getIdToken();
      if (idToken == null || idToken.trim().isEmpty) {
        return const FoodAnalysisFailure(
          'The app is not allowed to run an analysis right now.',
        );
      }

      final List<int> imageBytes = await image.readAsBytes();
      if (imageBytes.length > maxFoodAnalysisImageBytes) {
        return const FoodAnalysisFailure(_imageTooLargeMessage);
      }

      final String imageBase64 = base64Encode(imageBytes);
      final http.Response response = await _client
          .post(
            _endpoint ?? ApiConfig.analyzeFoodEndpoint,
            headers: <String, String>{
              HttpHeaders.authorizationHeader: 'Bearer $idToken',
              HttpHeaders.contentTypeHeader: 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'imageBase64': imageBase64,
              'mimeType': mimeTypeFor(image.path),
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return FoodAnalysisFailure(_messageForHttpError(response));
      }

      return _readResponse(jsonDecode(response.body));
    } on FirebaseAuthException {
      return const FoodAnalysisFailure(
        'The app is not allowed to run an analysis right now.',
      );
    } on TimeoutException {
      return const FoodAnalysisFailure(
        'The analysis took too long. Please try again.',
      );
    } on SocketException {
      return const FoodAnalysisFailure(
        'No internet connection. Connect and try again.',
      );
    } on http.ClientException {
      return const FoodAnalysisFailure(
        'No internet connection. Connect and try again.',
      );
    } on FileSystemException {
      return const FoodAnalysisFailure(
        'That photo could not be read. Please choose another one.',
      );
    } on FormatException {
      return const FoodAnalysisFailure(
        'The analysis came back in an unexpected format. Please try again.',
      );
    } catch (_) {
      return const FoodAnalysisFailure(
        'Something went wrong while analysing the photo. Please try again.',
      );
    }
  }

  /// Turns the callable's payload into an outcome.
  FoodAnalysisOutcome _readResponse(Object? data) {
    if (data is! Map) {
      throw const FormatException('response must be an object');
    }

    final Map<String, Object?> payload = Map<String, Object?>.from(data);

    switch (payload['status']) {
      case 'ok':
        final Object? analysis = payload['analysis'];
        if (analysis is! Map) {
          throw const FormatException('analysis must be an object');
        }
        return FoodAnalysisSuccess(
          FoodAnalysisResult.fromJson(Map<String, Object?>.from(analysis)),
        );

      case 'no_food_detected':
        final Object? reason = payload['reason'];
        return FoodAnalysisNoFood(
          reason is String && reason.trim().isNotEmpty
              ? reason
              : 'No food was found in this photo.',
        );

      default:
        throw const FormatException('unknown response status');
    }
  }

  /// Maps HTTP status and the backend's stable error code to safe UI text.
  String _messageForHttpError(http.Response response) {
    String? code;
    try {
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is Map) {
        final Object? rawCode = (decoded['error'] as Map)['code'];
        if (rawCode is String) code = rawCode;
      }
    } on FormatException {
      // Status-based fallback below is intentionally independent of body text.
    }

    if (response.statusCode == 401 || code == 'unauthenticated') {
      return 'The app is not allowed to run an analysis right now.';
    }
    if (response.statusCode == 429 || code == 'rate_limited') {
      return 'You have reached the scan limit. Please try again later.';
    }
    if (response.statusCode == 413 || code == 'image_too_large') {
      return _imageTooLargeMessage;
    }
    if (response.statusCode == 400 || code == 'invalid_argument') {
      return 'That photo could not be used. Try a different one.';
    }
    if (response.statusCode == 408 || response.statusCode == 504) {
      return 'The analysis took too long. Please try again.';
    }
    if (code == 'malformed_response') {
      return 'The analysis came back in an unexpected format. Please try again.';
    }
    if (response.statusCode >= 500) {
      if (code == 'unavailable') {
        return 'The analysis service is busy. Please try again in a moment.';
      }
      if (code == 'model_rate_limited') {
        return 'The analysis quota has run out. Please try again later.';
      }
    }
    return 'The photo could not be analysed. Please try again.';
  }
}

/// Picks the mime type from a file extension.
///
/// The backend only accepts jpeg, png and webp; anything else falls back to
/// jpeg, which is what the camera and the picker produce.
String mimeTypeFor(String path) {
  final String lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}
