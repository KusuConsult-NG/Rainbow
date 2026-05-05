# ============================================================
# Operation Rainbow — ProGuard / R8 Rules
# ============================================================

# Flutter core — keep all embedding classes
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-dontwarn io.flutter.**

# url_launcher plugin (Pigeon-generated API classes)
-keep class io.flutter.plugins.urllauncher.** { *; }
-dontwarn io.flutter.plugins.urllauncher.**

# Firebase — keep all reflection-used classes
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firestore / Cloud Messaging
-keep class com.google.firestore.** { *; }
-dontwarn com.google.firestore.**

# Geolocator plugin
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# Permission Handler plugin
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# Background service plugin
-keep class be.tramckrijte.workmanager.** { *; }
-keep class id.flutter.flutter_background_service.** { *; }
-dontwarn id.flutter.flutter_background_service.**

# Connectivity plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }
-dontwarn dev.fluttercommunity.plus.connectivity.**

# Google Maps / flutter_map (uses no native)
-dontwarn org.openstreetmap.**

# OkHttp (used by http package)
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# Prevent stripping of Kotlin metadata (Kotlin reflection)
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Keep Dart entry points used by Flutter
-keep class **.FlutterMain { *; }
-keep class **.GeneratedPluginRegistrant { *; }
