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
