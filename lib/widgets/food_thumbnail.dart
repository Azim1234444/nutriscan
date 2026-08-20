import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Rounded square that stands in for the food photo.
///
/// Phase 2 will swap the emoji for the image captured by the camera, so every
/// screen only has to change this one widget.
class FoodThumbnail extends StatelessWidget {
  const FoodThumbnail({super.key, required this.emoji, this.size = 48});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}
