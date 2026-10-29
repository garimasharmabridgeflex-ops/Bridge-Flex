import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';

/// Holds a photo the OS handed back after it had already destroyed the app to
/// free memory for the camera — see [captureLostPick].
final recoveredPickProvider = StateProvider<XFile?>((ref) => null);

/// Recovers a photo taken just before Android killed the app.
///
/// Android routinely destroys the app while a camera or gallery activity is on
/// screen. When it does, the plugin's result is "lost": the app restarts from
/// scratch and the user's photo is gone, which is what made the DBS upload feel
/// like it redirected away before the photo had even been submitted. Call this
/// once, as early as possible after startup; the next picker screen picks the
/// recovered file up from [recoveredPickProvider] and pre-fills it.
Future<void> captureLostPick(ProviderContainer container) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final response = await ImagePicker().retrieveLostData();
    if (response.isEmpty || response.file == null) return;
    container.read(recoveredPickProvider.notifier).state = response.file;
  } catch (e) {
    debugPrint('retrieveLostData failed: $e');
  }
}

/// Opens the OS file dialog, used for document uploads that accept the
/// original PDF alongside photo scans (DBS certificate, CV, right-to-work
/// evidence …). Returns a bytes-backed [XFile] so callers that only read
/// `readAsBytes()`/`name` behave identically on mobile and web.
Future<XFile?> pickDocumentFile() async {
  try {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return null;
    return files.first.xFile;
  } catch (e) {
    debugPrint('file picker error: $e');
    return null;
  }
}

/// Bottom sheet offering "Take photo" / "Choose from gallery" — previously
/// every picker in the app went straight to the gallery with no way to use
/// the camera at all — plus, for document uploads, a "Upload PDF or file"
/// option that opens the system file dialog.
///
/// On web the camera path is skipped (it crashes in browsers): image-only
/// callers go straight to the gallery, and document callers go straight to
/// the file dialog, where the browser's own picker accepts images too.
Future<XFile?> pickImageWithSourceSheet(
  BuildContext context, {
  int imageQuality = 85,
  bool allowFiles = false,
}) async {
  if (kIsWeb) {
    if (allowFiles) return pickDocumentFile();
    try {
      return await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: imageQuality);
    } catch (e) {
      debugPrint('pickImage Web error: $e');
      return null;
    }
  }

  final source = await showModalBottomSheet<Object>(
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
            if (allowFiles)
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Upload a file (PDF or scan)'),
                onTap: () => Navigator.pop(context, _fileOption),
              ),
          ],
        ),
      ),
    ),
  );
  if (source == null) return null;
  if (identical(source, _fileOption)) return pickDocumentFile();
  try {
    return await ImagePicker().pickImage(source: source as ImageSource, imageQuality: imageQuality);
  } catch (e) {
    debugPrint('pickImage error: $e');
    return null;
  }
}

/// Sentinel popped by the "Upload a file" tile — ImageSource has no value
/// that could collide with it.
const Object _fileOption = Object();
