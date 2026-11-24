import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
plugins {
    id("com.android.application")
    // NO id("kotlin-android") HERE, deliberately.
    //
    // `flutter create` on 3.50 does not apply it: the Kotlin plugin is
    // declared in settings.gradle.kts with `apply false`, and the Flutter
    // Gradle Plugin applies it. Applying it here is the legacy pattern, and
    // under AGP 9 it is what turns the old-DSL deprecation on `android { }`
    // into a script compilation error.
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // The Google Services Gradle plugin was applied here with no Firebase
    // dependency left in pubspec.yaml. It fails the build outright when
    // android/app/google-services.json is missing — and that file is gitignored
    // (it carries an API key), so every clean checkout failed `flutter build
    // apk --release`. Removed with the rest of the Firebase stack; a CI gate
    // keeps it out.
}

android {
    namespace = "com.RainbowEwer.RainbowEwer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"
    buildToolsVersion = "34.0.0"

    compileOptions {
        // Required for coreLibraryDesugaring and to fix D8 nest-class resolution errors
        // with url_launcher_android and Java 17 plugins on AGP 8.x
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.RainbowEwer.RainbowEwer"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            val keyProps = Properties()
            val keyPropsFile = rootProject.file("key.properties")
            if (keyPropsFile.exists()) {
                keyProps.load(keyPropsFile.inputStream())
                storeFile = rootProject.file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // key.properties is gitignored — it carries the keystore password
            // — so on any machine but the one that has it, the "release"
            // config above is assigned but empty and signing fails. Fall back
            // to the debug key so a clean checkout, and CI, can produce an
            // installable APK. A debug-signed build will not upgrade a Play
            // Store install and Android treats it as a separate app, which is
            // the correct outcome for a build made without the real key.
            signingConfig = if (rootProject.file("key.properties").exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    // Core library desugaring — required for isCoreLibraryDesugaringEnabled
    // and fixes D8 nest-mate resolution for Java 17 plugin classes (url_launcher, etc.)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.13.1")
}

// Kotlin compiles to the same bytecode as Java, said explicitly.
//
// This replaces `kotlinOptions { jvmTarget = "17" }` inside `android { }`,
// which AGP 9 rejects. The first attempt at that removal left NOTHING here,
// on the belief that the Flutter Gradle Plugin aligns Kotlin's target with
// `compileOptions`. It does not, and the build said so as soon as it ran on a
// JDK newer than the Java target:
//
//   Inconsistent JVM-target compatibility detected for tasks
//   'compileReleaseJavaWithJavac' (17) and 'compileReleaseKotlin' (21).
//
// Kotlin defaults its target to the JDK it is RUNNING on, while
// `compileOptions` above pins Java to 17. On the runner's old default JDK 17
// those two agreed by accident; pinning JDK 21 for AGP 9's lint pulled them
// apart. Setting it here keeps the app's bytecode exactly where it was and
// leaves the pair agreeing whatever JDK the build runs on.
kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
