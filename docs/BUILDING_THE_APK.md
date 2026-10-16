# Building a release APK

Four commands, then two checks. The checks matter more than the commands —
three separate times a fix has been reported as "still broken" from a handset
running the build from *before* the fix, and each one cost a round of
diagnosis of code that was already correct.

```bash
git pull origin main
cp -n .env.example .env          # only if you have no .env yet — see below
flutter clean
flutter pub get
flutter build apk --release
```

The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

## Then check two things

**1. Uninstall the old app before installing the new one.** Not "install over
the top". Android caches launcher icons per package, and an in-place upgrade
can keep showing you the previous icon for hours. If the icon is what you are
checking, uninstall first.

```bash
adb uninstall com.RainbowEwer.RainbowEwer || true
adb install build/app/outputs/flutter-apk/app-release.apk
```

**2. Read the version at the foot of the sign-in screen.** It is there for
exactly this. If it does not show the version you expect, you are looking at
an older APK and nothing else about the screen is worth diagnosing yet. The
version lives in `pubspec.yaml` (`version: 1.0.8+29` renders as `v1.0.8 (29)`).

The package id is still `com.RainbowEwer.RainbowEwer`, from before the
rename. It is deliberately left alone: an applicationId is an app's identity
to Android, and changing it makes the next build a different app rather than
an upgrade — every installed handset would keep the old one alongside it, and
anything published under the old id could not be updated. Nobody sees it but
the installer.

## Why `flutter clean` is in the list

It is not superstition. The launcher icons, the adaptive foreground and the
splash are generated files under `android/app/src/main/res/`, and Gradle
caches processed resources aggressively. An incremental build after an icon
change can package the previous PNGs. `flutter clean` costs about a minute
and removes the whole question.

Run `python3 scripts/build_brand_assets.py` first only if you changed
`Plateau_Eye_Logo.png`. The 37 generated assets are committed, so a plain
`git pull` already has them.

## Two files the build needs that git does not carry

Both are gitignored on purpose, so a fresh clone does not have them and the
build fails until they exist.

**`.env`** — `pubspec.yaml` declares it as a Flutter asset, so the build stops
with "asset not found" if it is missing. `cp .env.example .env` gives you a
working one; it holds no real credential.

**`android/key.properties`** — the release build signs with the keystore this
names:

```properties
storeFile=/absolute/path/to/plateau-eye.jks
storePassword=…
keyAlias=…
keyPassword=…
```

Without it the release signing config has no keystore, and what you get is
either a build failure or an unsigned APK that Android refuses to install. If
you are already installing release APKs today, you already have this file.
Keep it and the `.jks` off the repository — `android/.gitignore` covers
`key.properties`, `**/*.jks` and `**/*.keystore`, and a lost keystore cannot
be regenerated.

## Toolchain

The versions this repository is pinned to, all of which the Gradle files
declare rather than assume:

| | declared in |
| --- | --- |
| Java 17 or newer | `sourceCompatibility`, `jvmTarget` = 17 |
| Android Gradle Plugin 8.9.1 | `android/settings.gradle.kts` |
| Gradle 8.14 | `gradle-wrapper.properties` |
| NDK 28.2.13676358 | `android/app/build.gradle.kts` |
| Flutter stable | as CI uses |

The Java line is worth reading precisely. `jvmTarget = 17` is the bytecode
the build EMITS, not the JDK it has to RUN on: AGP 8.9.1 needs JDK 17 or
later and Gradle 8.14 is happy on 17 or 21, so either works and Android
Studio's bundled JDK is fine. What fails is **11 or older** — and the error
it gives names a class file version rather than a Java version, which is why
it is worth knowing in advance.

### After installing the Android SDK

Two things a first build needs that installing the SDK does not do:

```bash
flutter doctor --android-licenses      # accept them, or the build refuses
flutter doctor -v                      # read what it still says is missing
```

And Gradle has to be able to find the SDK — either `ANDROID_HOME` set in the
environment, or `sdk.dir=/path/to/Android/Sdk` in `android/local.properties`.
That file is gitignored, so it is yours to set and it is never wrong in the
repository; `flutter doctor -v` prints the path it found.

## A debug build instead

```bash
flutter run                      # on a connected handset, with hot reload
flutter build apk --debug        # an installable debug APK, no keystore needed
```

A debug build needs no `key.properties`. It is slower on the handset and the
startup error screen behaves differently — a release build strips `assert`,
which is why a crash at launch paints a blank grey rectangle there and a
readable message in debug. Reproduce handset problems in **release**.

## What this document is not

Nobody has run these commands end to end in CI. There is no Android SDK on
the CI runner, so the Android target is checked statically (that no Firebase
config is needed, that the launcher resources exist and match their hashes)
and built for real only on a developer's machine. If a step here is wrong,
it is wrong because it was written from the Gradle and pubspec configuration
rather than from a build that was watched. Say so and it gets fixed.
