import java.util.Properties
plugins {
    id("com.android.application")
    id("kotlin-android")
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

    kotlinOptions {
        jvmTarget = "17"
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
            signingConfig = signingConfigs.getByName("release")
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

flutter {
    source = "../.."
}
