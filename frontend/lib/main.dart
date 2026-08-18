import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/env.dart';
import 'core/firebase/firebase_options.dart';
import 'core/notifications/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register the background handler before any other Firebase interaction.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  if (Env.useLocalBackend) {
    final host = Env.devHost;
    await FirebaseAuth.instance.useAuthEmulator(host, Env.authEmulatorPort);
    FirebaseFirestore.instance.useFirestoreEmulator(host, Env.firestoreEmulatorPort);
    await FirebaseStorage.instance.useStorageEmulator(host, Env.storageEmulatorPort);
  }

  runApp(const ProviderScope(child: KFlexApp()));
}

