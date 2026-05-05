import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'services/background_tracking_service.dart';
import 'services/alert_service.dart';
import 'app.dart';

import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await Firebase.initializeApp();
    await AlertService().flushOfflineQueue();
    return Future.value(true);
  });
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  Workmanager().initialize(callbackDispatcher);
  Workmanager().registerPeriodicTask(
    "1",
    "offlineSyncTask",
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Register the background tracking isolate
  await BackgroundTrackingService().initializeService();

  // Flushes the offline emergency payload queue natively when network is restored
  Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
    if (!results.contains(ConnectivityResult.none)) {
      AlertService().flushOfflineQueue();
    }
  });

  // Secure App Architecture — blocks unverified API calls
  try {
    if (kDebugMode) {
      await FirebaseAppCheck.instance.activate(
        // Use DebugProvider for local testing to prevent Play Integrity crash
        providerAndroid: const AndroidDebugProvider(), 
      );
    } else {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: const AndroidPlayIntegrityProvider(),
        providerApple: const AppleDeviceCheckProvider(),
      );
    }
  } catch (e) {
    debugPrint('⚠️ App Check Init Failed: $e');
  }

  await dotenv.load(fileName: ".env");
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: RainbowApp()));
}
