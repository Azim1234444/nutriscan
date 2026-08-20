// Widget tests for the Phase 2A image acquisition flow.
//
// The picker is faked, so these tests never touch the camera or the platform
// channels - they only check how the screen reacts to each possible result.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/app/app_routes.dart';
import 'package:nutriscan/models/food_analysis_result.dart';
import 'package:nutriscan/screens/scan/scan_screen.dart';
import 'package:nutriscan/services/food_analysis_service.dart';
import 'package:nutriscan/services/image_picker_service.dart';
import 'package:nutriscan/theme/app_theme.dart';

/// Returns whatever result the test asks for instead of opening the camera.
class _FakeImagePickerService implements ImagePickerService {
  _FakeImagePickerService(this.result);

  ImagePickResult result;
  int cameraCalls = 0;
  int galleryCalls = 0;

  @override
  Future<ImagePickResult> takePhoto() async {
    cameraCalls++;
    return result;
  }

  @override
  Future<ImagePickResult> pickFromGallery() async {
    galleryCalls++;
    return result;
  }
}

/// Returns a canned outcome instead of calling the Cloud Function.
class _FakeFoodAnalysisService implements FoodAnalysisService {
  _FakeFoodAnalysisService(this.outcome);

  final FoodAnalysisOutcome outcome;
  int calls = 0;

  @override
  Future<FoodAnalysisOutcome> analyze(File image) async {
    calls++;
    return outcome;
  }
}

/// A stand-in estimate, with the numbers a real analysis would carry.
final FoodAnalysisResult _sampleResult = FoodAnalysisResult(
  foodName: 'Grilled chicken salad',
  description: 'Mixed leaves with sliced grilled chicken breast.',
  portionGrams: 320,
  calories: 465,
  proteinG: 42,
  carbsG: 18,
  fatG: 24,
  fiberG: 6,
  confidence: 0.78,
  assumptions: const <String>['Dressing assumed to be olive oil based.'],
  items: const <AnalyzedFoodItem>[
    AnalyzedFoodItem(name: 'Grilled chicken breast', portionGrams: 150),
  ],
);

/// Smallest possible valid PNG, so `Image.file` has something real to point at.
final Uint8List _onePixelPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// Pumps the screen on a phone-sized surface.
///
/// The default 800x600 test window is too short for the square viewfinder plus
/// the buttons below it, and a ListView does not build off-screen children.
Future<void> _pumpScanScreen(
  WidgetTester tester,
  ImagePickerService service, {
  FoodAnalysisService? analysisService,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: ScanScreen(
        imagePickerService: service,
        foodAnalysisService: analysisService,
      ),
    ),
  );
}

void main() {
  // File I/O has to happen outside testWidgets: inside a test body the fake
  // async clock never completes real disk operations, so an await there hangs.
  late Directory tempDirectory;
  late File testImage;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp('nutriscan_test');
    testImage = File('${tempDirectory.path}/meal.png');
    await testImage.writeAsBytes(_onePixelPng);
  });

  tearDownAll(() async {
    await tempDirectory.delete(recursive: true);
  });

  testWidgets('starts on the capture view with both source buttons', (
    WidgetTester tester,
  ) async {
    await _pumpScanScreen(
      tester,
      _FakeImagePickerService(const ImagePickResult.cancelled()),
    );

    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);
    expect(find.text('Analyze Food'), findsNothing);
  });

  testWidgets('cancelling the picker leaves the capture view untouched', (
    WidgetTester tester,
  ) async {
    final fake = _FakeImagePickerService(const ImagePickResult.cancelled());
    await _pumpScanScreen(tester, fake);

    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();

    expect(fake.cameraCalls, 1);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Analyze Food'), findsNothing);
    // No error is reported for a cancellation.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a denied permission shows a friendly message', (
    WidgetTester tester,
  ) async {
    final fake = _FakeImagePickerService(
      const ImagePickResult.permissionDenied('Camera access is off.'),
    );
    await _pumpScanScreen(tester, fake);

    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();

    expect(find.text('Camera access is off.'), findsOneWidget);
    expect(find.text('Analyze Food'), findsNothing);
  });

  testWidgets('a picked image switches to the preview actions', (
    WidgetTester tester,
  ) async {
    final fake = _FakeImagePickerService(ImagePickResult.success(testImage));
    await _pumpScanScreen(tester, fake);

    await tester.tap(find.text('Choose from Gallery'));
    await tester.pumpAndSettle();

    expect(fake.galleryCalls, 1);
    expect(find.text('Retake Photo'), findsOneWidget);
    expect(find.text('Choose Another Image'), findsOneWidget);
    expect(find.text('Analyze Food'), findsOneWidget);
    expect(find.text('Take Photo'), findsNothing);
  });

  testWidgets('Analyze Food opens the result screen with the estimate', (
    WidgetTester tester,
  ) async {
    final picker = _FakeImagePickerService(ImagePickResult.success(testImage));
    final analysis = _FakeFoodAnalysisService(
      FoodAnalysisSuccess(_sampleResult),
    );
    await _pumpScanScreen(tester, picker, analysisService: analysis);

    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze Food'));
    await tester.pumpAndSettle();

    expect(analysis.calls, 1);
    expect(find.text('Grilled chicken salad'), findsOneWidget);
    expect(find.text('465'), findsOneWidget);
    expect(
      find.text('Nutrition values are AI estimates and may not be exact.'),
      findsOneWidget,
    );
  });

  testWidgets('a photo without food reports it instead of showing numbers', (
    WidgetTester tester,
  ) async {
    final picker = _FakeImagePickerService(ImagePickResult.success(testImage));
    final analysis = _FakeFoodAnalysisService(
      const FoodAnalysisNoFood('The photo shows a laptop keyboard.'),
    );
    await _pumpScanScreen(tester, picker, analysisService: analysis);

    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze Food'));
    await tester.pumpAndSettle();

    expect(find.text('No food found in this photo'), findsOneWidget);
    expect(find.text('The photo shows a laptop keyboard.'), findsOneWidget);
    // The user stays on the scan screen and can try another photo.
    expect(find.text('Analyze Food'), findsOneWidget);
  });

  testWidgets('a failed analysis explains what happened', (
    WidgetTester tester,
  ) async {
    final picker = _FakeImagePickerService(ImagePickResult.success(testImage));
    final analysis = _FakeFoodAnalysisService(
      const FoodAnalysisFailure(
        'The analysis service is busy. Please try again in a moment.',
      ),
    );
    await _pumpScanScreen(tester, picker, analysisService: analysis);

    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze Food'));
    await tester.pumpAndSettle();

    expect(find.text('Analysis failed'), findsOneWidget);
    expect(
      find.text('The analysis service is busy. Please try again in a moment.'),
      findsOneWidget,
    );
  });
}
