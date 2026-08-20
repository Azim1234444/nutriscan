import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../models/food_analysis_result.dart';
import '../../screens/result/analysis_result_screen.dart';
import '../../services/food_analysis_service.dart';
import '../../services/image_picker_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';

/// The Scan tab.
///
/// The user takes or picks a photo, previews it, and sends it to the
/// `analyzeFoodImage` Cloud Function. The photo stays in memory - it is not
/// saved anywhere - and the app never talks to the AI model directly.
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    this.imagePickerService,
    this.foodAnalysisService,
  });

  /// Overridable so tests can supply a fake. Null means "use the real
  /// plugin-backed service".
  final ImagePickerService? imagePickerService;

  /// Overridable so tests can drive the analysis without a backend.
  final FoodAnalysisService? foodAnalysisService;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final ImagePickerService _imagePicker =
      widget.imagePickerService ?? ImagePickerService();

  late final FoodAnalysisService _foodAnalysis =
      widget.foodAnalysisService ?? FoodAnalysisService();

  /// The photo the user is working with, or null while nothing is chosen.
  File? _selectedImage;

  /// True while the camera or gallery is open, so the buttons cannot be
  /// triggered twice.
  bool _isPicking = false;

  /// True while the backend is analysing the photo.
  bool _isAnalyzing = false;

  /// Set when an analysis ends without a result, e.g. no food in the photo.
  _AnalysisNotice? _notice;

  Future<void> _takePhoto() => _pick(_imagePicker.takePhoto);

  Future<void> _chooseFromGallery() => _pick(_imagePicker.pickFromGallery);

  /// Runs a pick and turns its result into UI state.
  Future<void> _pick(Future<ImagePickResult> Function() pickImage) async {
    if (_isPicking || _isAnalyzing) return;
    setState(() {
      _isPicking = true;
      // A new photo invalidates whatever the last analysis said.
      _notice = null;
    });

    final ImagePickResult result = await pickImage();

    // The screen can be disposed while the camera is in the foreground.
    if (!mounted) return;

    setState(() {
      _isPicking = false;
      if (result.isSuccess) {
        _selectedImage = result.file;
      }
    });

    // Cancelling is normal, so it carries no message and changes nothing.
    final String? message = result.message;
    if (message != null) _showMessage(message);
  }

  /// Sends the photo to the backend and opens the result screen.
  Future<void> _analyzeFood() async {
    final File? image = _selectedImage;
    if (image == null || _isAnalyzing) return;

    setState(() {
      _isAnalyzing = true;
      _notice = null;
    });

    final FoodAnalysisOutcome outcome = await _foodAnalysis.analyze(image);

    if (!mounted) return;
    setState(() => _isAnalyzing = false);

    switch (outcome) {
      case FoodAnalysisSuccess(:final FoodAnalysisResult result):
        Navigator.of(context).pushNamed(
          AppRoutes.analysisResult,
          arguments: AnalysisResultArgs(image: image, result: result),
        );
      case FoodAnalysisNoFood(:final String reason):
        setState(() {
          _notice = _AnalysisNotice(
            icon: Icons.no_food_outlined,
            title: 'No food found in this photo',
            message: reason,
          );
        });
      case FoodAnalysisFailure(:final String message):
        setState(() {
          _notice = _AnalysisNotice(
            icon: Icons.error_outline_rounded,
            title: 'Analysis failed',
            message: message,
          );
        });
    }
  }

  /// Drops the current image, e.g. when it turns out to be unreadable.
  void _clearImage() {
    setState(() {
      _selectedImage = null;
      _notice = null;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final File? image = _selectedImage;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Food')),
      body: SafeArea(
        child: image == null
            ? _CaptureView(
                isPicking: _isPicking,
                onTakePhoto: _takePhoto,
                onChooseFromGallery: _chooseFromGallery,
              )
            : _PreviewView(
                image: image,
                isPicking: _isPicking,
                isAnalyzing: _isAnalyzing,
                notice: _notice,
                onRetake: _takePhoto,
                onChooseAnother: _chooseFromGallery,
                onAnalyze: _analyzeFood,
                onImageUnreadable: _clearImage,
              ),
      ),
    );
  }
}

/// Shown before an image is chosen: the viewfinder and the two source buttons.
class _CaptureView extends StatelessWidget {
  const _CaptureView({
    required this.isPicking,
    required this.onTakePhoto,
    required this.onChooseFromGallery,
  });

  final bool isPicking;
  final VoidCallback onTakePhoto;
  final VoidCallback onChooseFromGallery;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: <Widget>[
        Text('Capture your meal', style: text.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Place the whole plate inside the frame and keep the camera steady '
          'for the most accurate result.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),

        const _ScanFrame(),
        const SizedBox(height: AppSpacing.lg),

        FilledButton.icon(
          onPressed: isPicking ? null : onTakePhoto,
          icon: const Icon(Icons.photo_camera_rounded),
          label: const Text('Take Photo'),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: isPicking ? null : onChooseFromGallery,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from Gallery'),
        ),
        const SizedBox(height: AppSpacing.lg),

        const _AiInfoCard(),
      ],
    );
  }
}

/// Shown once an image is chosen: the photo plus the three follow-up actions.
class _PreviewView extends StatelessWidget {
  const _PreviewView({
    required this.image,
    required this.isPicking,
    required this.isAnalyzing,
    required this.notice,
    required this.onRetake,
    required this.onChooseAnother,
    required this.onAnalyze,
    required this.onImageUnreadable,
  });

  final File image;
  final bool isPicking;
  final bool isAnalyzing;
  final _AnalysisNotice? notice;
  final VoidCallback onRetake;
  final VoidCallback onChooseAnother;
  final VoidCallback onAnalyze;
  final VoidCallback onImageUnreadable;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: <Widget>[
        Text('Check your photo', style: text.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Make sure the whole meal is visible and in focus before you '
          'continue.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),

        _ImagePreview(image: image, onImageUnreadable: onImageUnreadable),
        const SizedBox(height: AppSpacing.lg),

        if (notice != null) ...<Widget>[
          _NoticeCard(notice: notice!),
          const SizedBox(height: AppSpacing.lg),
        ],

        OutlinedButton.icon(
          onPressed: isPicking || isAnalyzing ? null : onRetake,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retake Photo'),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: isPicking || isAnalyzing ? null : onChooseAnother,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose Another Image'),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: isPicking || isAnalyzing ? null : onAnalyze,
          icon: isAnalyzing
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.auto_awesome_rounded),
          label: Text(isAnalyzing ? 'Analysing photo…' : 'Analyze Food'),
        ),
        const SizedBox(height: AppSpacing.lg),

        const _AiInfoCard(),
      ],
    );
  }
}

/// Why the last analysis produced no result.
class _AnalysisNotice {
  const _AnalysisNotice({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;
}

/// Explains a no-food or failed analysis in place, above the buttons, so the
/// user can read it while deciding what to do next.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});

  final _AnalysisNotice notice;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(notice.icon, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(notice.title, style: text.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(notice.message, style: text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The chosen photo, with a friendly fallback if the file cannot be decoded.
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image, required this.onImageUnreadable});

  final File image;
  final VoidCallback onImageUnreadable;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.cardRadius,
      child: AspectRatio(
        aspectRatio: 1,
        child: Image.file(
          image,
          fit: BoxFit.cover,
          errorBuilder: (BuildContext context, Object error, StackTrace? _) {
            return _UnreadableImage(onTryAgain: onImageUnreadable);
          },
        ),
      ),
    );
  }
}

class _UnreadableImage extends StatelessWidget {
  const _UnreadableImage({required this.onTryAgain});

  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return ColoredBox(
      color: AppColors.primarySoft,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'This image could not be displayed',
                style: text.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: onTryAgain,
                child: const Text('Pick a different image'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Camera-style viewfinder: a soft square with bracket corners.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: AppColors.outline),
        ),
        child: Stack(
          children: <Widget>[
            const Positioned(
              top: AppSpacing.lg,
              left: AppSpacing.lg,
              child: _FrameCorner(isTop: true, isLeft: true),
            ),
            const Positioned(
              top: AppSpacing.lg,
              right: AppSpacing.lg,
              child: _FrameCorner(isTop: true, isLeft: false),
            ),
            const Positioned(
              bottom: AppSpacing.lg,
              left: AppSpacing.lg,
              child: _FrameCorner(isTop: false, isLeft: true),
            ),
            const Positioned(
              bottom: AppSpacing.lg,
              right: AppSpacing.lg,
              child: _FrameCorner(isTop: false, isLeft: false),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.center_focus_strong_rounded,
                      size: 64,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'No photo yet',
                      style: text.titleMedium?.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Take a photo of your meal or choose one from your '
                      'gallery.',
                      style: text.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One bracket in a corner of the scan frame.
class _FrameCorner extends StatelessWidget {
  const _FrameCorner({required this.isTop, required this.isLeft});

  final bool isTop;
  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    const BorderSide side = BorderSide(color: AppColors.primary, width: 3);

    return Container(
      height: 28,
      width: 28,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? side : BorderSide.none,
          bottom: isTop ? BorderSide.none : side,
          left: isLeft ? side : BorderSide.none,
          right: isLeft ? BorderSide.none : side,
        ),
      ),
    );
  }
}

/// Explains what happens to the photo when the user runs an analysis.
class _AiInfoCard extends StatelessWidget {
  const _AiInfoCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      color: AppColors.primarySoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.auto_awesome_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'How the analysis works',
                  style: text.titleMedium?.copyWith(
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your photo is sent to NutriScan, where an AI model identifies the '
            'food and estimates its calories, protein, carbohydrates and fat. '
            'The photo is not saved, and the results are estimates.',
            style: text.bodyMedium?.copyWith(color: AppColors.primaryDark),
          ),
        ],
      ),
    );
  }
}
