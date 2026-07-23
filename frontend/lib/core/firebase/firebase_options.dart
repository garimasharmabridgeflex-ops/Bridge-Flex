import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Hand-written, matching backend/.firebaserc's demo project
/// ("demo-bridgeflex"). A *demo-* project ID is special-cased by the
/// Firebase SDKs: it never talks to real Firebase, only emulators — exactly
/// the "no card, fully local" posture ARCHITECTURE.md commits to for Phase 1.
/// Swap this file for the real one (`flutterfire configure`) once a real
/// Firebase project exists and Blaze/go-live is decided.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-bridgeflex',
    authDomain: 'demo-bridgeflex.firebaseapp.com',
    storageBucket: 'demo-bridgeflex.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-bridgeflex',
    storageBucket: 'demo-bridgeflex.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-bridgeflex',
    storageBucket: 'demo-bridgeflex.appspot.com',
    iosBundleId: 'com.bridgeflex.bridgeflexApp',
  );
}
