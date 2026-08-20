import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// What happened when the user tried to pick an image.
enum ImagePickOutcome {
  /// An image was captured or chosen and is ready to use.
  success,

  /// The user backed out of the camera or the gallery. Not an error.
  cancelled,

  /// The camera or photo library permission was refused.
  permissionDenied,

  /// The device reported no usable camera.
  cameraUnavailable,

  /// Anything else: a broken file, a busy picker, an unexpected platform error.
  failed,
}

/// The result of one pick attempt.
///
/// Screens read [outcome] to decide what to show, so they never have to catch
/// platform exceptions themselves.
class ImagePickResult {
  const ImagePickResult._(this.outcome, {this.file, this.message});

  const ImagePickResult.success(File file)
    : this._(ImagePickOutcome.success, file: file);

  const ImagePickResult.cancelled() : this._(ImagePickOutcome.cancelled);

  const ImagePickResult.permissionDenied(String message)
    : this._(ImagePickOutcome.permissionDenied, message: message);

  const ImagePickResult.cameraUnavailable(String message)
    : this._(ImagePickOutcome.cameraUnavailable, message: message);

  const ImagePickResult.failed(String message)
    : this._(ImagePickOutcome.failed, message: message);

  final ImagePickOutcome outcome;

  /// The chosen image. Only set when [outcome] is [ImagePickOutcome.success].
  final File? file;

  /// User-friendly text to show. Null for success and cancellation.
  final String? message;

  bool get isSuccess => outcome == ImagePickOutcome.success;
  bool get isCancelled => outcome == ImagePickOutcome.cancelled;
}

/// Wraps the `image_picker` plugin so screens deal with plain results instead
/// of platform channels and exceptions.
///
/// Phase 2A only acquires the image. Nothing is uploaded, analysed or saved to
/// permanent storage - the file stays in the system temp directory that the
/// picker wrote it to.
class ImagePickerService {
  ImagePickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Longest edge of the image we keep, in pixels. Full-size camera photos are
  /// far larger than anything the UI (or a later AI request) needs.
  static const double _maxDimension = 1600;

  /// JPEG quality after resizing.
  static const int _imageQuality = 85;

  /// Opens the system camera.
  Future<ImagePickResult> takePhoto() => _pick(ImageSource.camera);

  /// Opens the system gallery / photo picker.
  Future<ImagePickResult> pickFromGallery() => _pick(ImageSource.gallery);

  Future<ImagePickResult> _pick(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: _maxDimension,
        maxHeight: _maxDimension,
        imageQuality: _imageQuality,
        preferredCameraDevice: CameraDevice.rear,
      );

      // Null means the user pressed back or cancelled - a normal action.
      if (picked == null) return const ImagePickResult.cancelled();

      final File file = File(picked.path);
      if (!await file.exists() || await file.length() == 0) {
        return const ImagePickResult.failed(
          'That image could not be read. Please try another one.',
        );
      }

      return ImagePickResult.success(file);
    } on PlatformException catch (error) {
      return _describe(error, source);
    } catch (_) {
      return ImagePickResult.failed(_unexpectedMessage(source));
    }
  }

  /// Turns a plugin error code into something a user can act on.
  ImagePickResult _describe(PlatformException error, ImageSource source) {
    switch (error.code) {
      case 'camera_access_denied':
        return const ImagePickResult.permissionDenied(
          'Camera access is off. Allow the camera in Settings to scan a meal.',
        );
      case 'photo_access_denied':
        return const ImagePickResult.permissionDenied(
          'Photo access is off. Allow photos in Settings to choose an image.',
        );
      case 'no_available_camera':
        return const ImagePickResult.cameraUnavailable(
          'No camera is available on this device. Choose an image instead.',
        );
      case 'already_active':
      case 'multiple_request':
        return const ImagePickResult.failed(
          'Another image request is still open. Please try again.',
        );
      case 'invalid_image':
      case 'invalid_source':
        return const ImagePickResult.failed(
          'That file is not a supported image. Please try another one.',
        );
      default:
        return ImagePickResult.failed(_unexpectedMessage(source));
    }
  }

  String _unexpectedMessage(ImageSource source) {
    return source == ImageSource.camera
        ? 'The camera could not be opened. Please try again.'
        : 'The gallery could not be opened. Please try again.';
  }
}
