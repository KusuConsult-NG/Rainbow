// GENERATED FILE — DO NOT EDIT MANUALLY
// Provides DefaultFirebaseOptions for all platforms including background isolates.
// Generated from google-services.json and GoogleService-Info.plist
// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Documentation for this public member.

class DefaultFirebaseOptions {
  /// Documentation for this public member.
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      // ignore: no_default_cases, Stylistic override to match system design
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  /// Documentation for this public member.

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '***REMOVED-SECRET***',
    appId: '1:787216891713:android:2c3e5e242116a993a82bc0',
    messagingSenderId: '787216891713',
    projectId: 'rainbow-97f1e',
    databaseURL: 'https://rainbow-97f1e-default-rtdb.firebaseio.com',
    storageBucket: 'rainbow-97f1e.firebasestorage.app',
  );

  /// Documentation for this public member.

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: '***REMOVED-SECRET***',
    appId: '1:787216891713:ios:e0facbb9c6a7b700a82bc0',
    messagingSenderId: '787216891713',
    projectId: 'rainbow-97f1e',
    databaseURL: 'https://rainbow-97f1e-default-rtdb.firebaseio.com',
    storageBucket: 'rainbow-97f1e.firebasestorage.app',
    iosBundleId: 'com.RainbowEwer.RainbowEwer',
  );

  /// Documentation for this public member.

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: '***REMOVED-SECRET***',
    appId: '1:787216891713:web:a82bc0rainbow',
    messagingSenderId: '787216891713',
    projectId: 'rainbow-97f1e',
    databaseURL: 'https://rainbow-97f1e-default-rtdb.firebaseio.com',
    storageBucket: 'rainbow-97f1e.firebasestorage.app',
  );
}
