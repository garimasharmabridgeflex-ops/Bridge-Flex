import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import '../config/env.dart';

/// Branches on [Env.useLocalBackend] (the same `--dart-define=USE_LOCAL_
/// BACKEND=false` flag that switches [Env.functionUri] to real Cloud
/// Functions URLs) so one build can target either the local `demo-bridgeflex`
/// project — a `demo-*` project ID is special-cased by the Firebase SDKs to
/// only ever talk to emulators, never real Firebase — or the real
/// `kvision-503115` project registered via `firebase apps:create` (config
/// pulled with `firebase apps:sdkconfig`). Without this branch, a release
/// build would silently keep initializing against the emulator project and
/// every sign-in/Firestore call would fail on a real device with no
/// emulator to reach.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return Env.useLocalBackend ? _demoWeb : _prodWeb;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return Env.useLocalBackend ? _demoAndroid : _prodAndroid;
      case TargetPlatform.iOS:
        return Env.useLocalBackend ? _demoIos : _prodIos;
      default:
        return Env.useLocalBackend ? _demoWeb : _prodWeb;
    }
  }

  static const FirebaseOptions _demoWeb = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-bridgeflex',
    authDomain: 'demo-bridgeflex.firebaseapp.com',
    storageBucket: 'demo-bridgeflex.appspot.com',
  );

  static const FirebaseOptions _demoAndroid = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-bridgeflex',
    storageBucket: 'demo-bridgeflex.appspot.com',
  );

  static const FirebaseOptions _demoIos = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-bridgeflex',
    storageBucket: 'demo-bridgeflex.appspot.com',
    iosBundleId: 'com.bridgeflex.bridgeflexApp',
  );

  // Real project — registered via `firebase apps:create {android,ios,web}
  // --project=kvision-503115`; config pulled with `firebase apps:sdkconfig`.
  static const FirebaseOptions _prodWeb = FirebaseOptions(
    apiKey: 'AIzaSyAZGlxYsLX8Bzb37YLseaKfDpwbJ96D5nE',
    appId: '1:288297326448:web:1e44d9230d353911e3e1b5',
    messagingSenderId: '288297326448',
    projectId: 'kvision-503115',
    authDomain: 'kvision-503115.firebaseapp.com',
    storageBucket: 'kvision-503115.firebasestorage.app',
    measurementId: 'G-748FX1LB66',
  );

  static const FirebaseOptions _prodAndroid = FirebaseOptions(
    apiKey: 'AIzaSyCfS1s21CuzXvqAz2aeJvRFO_utHh3VHug',
    appId: '1:288297326448:android:c3146b6d47e68b3ae3e1b5',
    messagingSenderId: '288297326448',
    projectId: 'kvision-503115',
    storageBucket: 'kvision-503115.firebasestorage.app',
  );

  static const FirebaseOptions _prodIos = FirebaseOptions(
    apiKey: 'AIzaSyAnNhVSSoN-WJsG8GA1ZGjnvY2VKcVBtNw',
    appId: '1:288297326448:ios:9a40897cfa6281ebe3e1b5',
    messagingSenderId: '288297326448',
    projectId: 'kvision-503115',
    storageBucket: 'kvision-503115.firebasestorage.app',
    iosBundleId: 'com.bridgeflex.bridgeflexApp',
  );
}
