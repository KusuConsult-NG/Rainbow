allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Plugins that compile against an Android API older than their own
// dependencies require.
//
//     Dependency 'androidx.annotation:annotation-experimental:1.4.0' requires
//     libraries and applications that depend on it to compile against version
//     34 or later.
//     :flutter_webrtc is currently compiled against android-31.
//
// The app compiles against 36 (flutter.compileSdkVersion). flutter_webrtc
// pins itself to 31, and AGP fails the build rather than let a library be
// compiled against an API older than its own dependencies demand. Several
// other plugins are in the same position.
//
// Raising the floor for library subprojects is the usual Flutter answer and
// is safe in the direction it moves: compileSdk only decides which APIs the
// code may reference while compiling. It does NOT change minSdk, so no device
// loses support, and it does NOT change targetSdk, so no runtime behaviour
// changes. The plugin's own source is unchanged.
//
// KEEP THIS IN STEP WITH android/app/build.gradle.kts. The app takes its
// compileSdk from flutter.compileSdkVersion; this floor has to be the same
// number or a plugin can end up compiled against an older API than the app.
val pluginCompileSdkFloor = 36

// Raising the floor has to happen AFTER each subproject's own build script
// and has to cope with some of them already being evaluated. Two attempts got
// this wrong, each caught by the APK job:
//
//   1. plugins.withId("com.android.library") fires when the plugin is
//      APPLIED, before the subproject's `android { }` block runs, so
//      flutter_webrtc set compileSdk 31 straight over the top. Same error
//      again, byte for byte, which is how the ordering showed itself.
//   2. A plain afterEvaluate then threw outright:
//
//          Cannot run Project.afterEvaluate(Action) when the project is
//          already evaluated.
//
//      because `subprojects { project.evaluationDependsOn(":app") }` above
//      forces :app to be evaluated while the other subprojects configure. By
//      the time this block reaches :app it is finished, and registering a
//      callback on a finished project is an error. Moving this block earlier
//      in the file does not help: :app is evaluated by the OTHER subprojects,
//      not by position here.
//
// So: apply immediately where the project is already evaluated, and defer
// only where it is not. :app is an application, not a library, so
// findByType(LibraryExtension) is null there and this is a no-op for it.
fun raisePluginCompileSdk(target: Project, floor: Int) {
    val ext = target.extensions
        .findByType(com.android.build.gradle.LibraryExtension::class.java)
    if (ext != null && (ext.compileSdk ?: 0) < floor) {
        ext.compileSdk = floor
    }
}

subprojects {
    if (state.executed) {
        raisePluginCompileSdk(this, pluginCompileSdkFloor)
    } else {
        afterEvaluate { raisePluginCompileSdk(this, pluginCompileSdkFloor) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Every plugin compiles at Kotlin language level 2.0 at least: left to
// themselves some still ask for 1.6 or 1.8, and the Kotlin 2.4.20 compiler
// refuses both outright —
//
//     e: Language version 1.8 is no longer supported; use version 2.0 or
//        greater instead.
//     Execution failed for task ':battery_plus:compileReleaseKotlin'
//
// This floor used to be 1.8, which was right for Kotlin 2.2.20 and is now the
// thing that breaks the build. The note that used to sit here said "Nothing in
// CI builds the APK, which is how that went unnoticed" — and it went unnoticed
// a second time, for the same reason, until this branch added a job that does.
//
// Written as fromVersion("2.0"), not KotlinVersion.KOTLIN_2_0: the constant is
// marked an error by the Kotlin Gradle plugin, which makes THIS script fail to
// compile, and `flutter build apk` then stops before building anything.
//
// The real fix is upstream. Twelve plugins apply their own Kotlin Gradle
// Plugin — battery_plus, flutter_foreground_task, flutter_tts, flutter_webrtc,
// image_picker_android, package_info_plus, record_android, sentry_flutter,
// share_plus, shared_preferences_android, speech_to_text, workmanager_android —
// and Flutter warns that future versions will refuse to build an app whose
// plugins do that. Upgrading them to releases that support Built-in Kotlin is
// a dependency decision with real behavioural risk for a safety app, so it is
// not made here. This floor keeps the build working until it is.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.fromVersion("2.0"))
            apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.fromVersion("2.0"))
        }
    }
}
