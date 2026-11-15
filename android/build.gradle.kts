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

// Every plugin compiles at Kotlin language level 1.8 at least: some, Sentry's
// among them, still ask for 1.6, which the Kotlin 2.2.20 compiler refuses.
//
// Written as fromVersion("1.8"), not KotlinVersion.KOTLIN_1_8: the Kotlin 2.2
// Gradle plugin marks that constant as an error, so this script itself failed
// to compile and `flutter build apk` stopped before building anything.
// Nothing in CI builds the APK, which is how that went unnoticed.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.fromVersion("1.8"))
            apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.fromVersion("1.8"))
        }
    }
}
