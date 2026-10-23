import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';

/// Bottom sheet offering "Take photo" / "Choose from gallery" — previously
/// every picker in the app went straight to the gallery with no way to use
/// the camera at all. On web, file picker is used directly to avoid camera
/// permission crashes.
Future<XFile?> pickImageWithSourceSheet(
  BuildContext context, {
  int imageQuality = 85,
}) async {
  if (kIsWeb) {
    try {
      return await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: imageQuality);
    } catch (e) {
      debugPrint('pickImage Web error: $e');
      return null;
    }
  }

  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
  if (source == null) return null;
  try {
    return await ImagePicker().pickImage(source: source, imageQuality: imageQuality);
  } catch (e) {
    debugPrint('pickImage error: $e');
    return null;
  }
}
