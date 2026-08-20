import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';

import '../models/food_analysis_result.dart';

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

/// Sends a food photo to the `analyzeFoodImage` callable and returns what came
/// back.
///
/// The app never talks to Gemini directly and never holds an AI API key: the
/// photo goes to the Cloud Function, which keeps the key server-side.
class FoodAnalysisService {
  FoodAnalysisService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Give up if the whole round trip takes longer than this.
  static const Duration _timeout = Duration(seconds: 70);

  /// Analyses [image] and never throws - failures come back as
  /// [FoodAnalysisFailure].
  Future<FoodAnalysisOutcome> analyze(File image) async {
    try {
      final String imageBase64 = base64Encode(await image.readAsBytes());

      final HttpsCallableResult<Object?> response = await _functions
          .httpsCallable('analyzeFoodImage')
          .call<Object?>(<String, Object?>{
            'imageBase64': imageBase64,
            'mimeType': mimeTypeFor(image.path),
          })
          .timeout(_timeout);

      return _readResponse(response.data);
    } on FirebaseFunctionsException catch (error) {
      return FoodAnalysisFailure(_messageForCallableError(error));
    } on TimeoutException {
      return const FoodAnalysisFailure(
        'The analysis took too long. Please try again.',
      );
    } on SocketException {
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

  /// Maps a callable error code to something worth showing the user.
  String _messageForCallableError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unavailable':
        return 'The analysis service is busy. Please try again in a moment.';
      case 'resource-exhausted':
        return 'The analysis quota has run out. Please try again later.';
      case 'deadline-exceeded':
        return 'The analysis took too long. Please try again.';
      case 'invalid-argument':
        return 'That photo could not be used. Try a different one.';
      case 'unauthenticated':
      case 'permission-denied':
        return 'The app is not allowed to run an analysis right now.';
      default:
        return 'The photo could not be analysed. Please try again.';
    }
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
