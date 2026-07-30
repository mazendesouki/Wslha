plugins {
    id("com.android.application")
    // Needed for the `kotlin { compilerOptions { ... } }` block below —
    // without it, Gradle can't resolve `kotlin` as the Kotlin plugin
    // extension and mistakes it for DependencyHandler.kotlin(...).
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "co.wslha.wslha_app"
    // Pinned above the Flutter-default NDK — geolocator/path_provider/
    // shared_preferences/url_launcher's Android plugins require 28.2.13676358;
    // newer NDKs stay backward compatible with older ones.
    ndkVersion = "28.2.13676358"
    // Stays on 36 — the "android-37" SDK platform package has a naming bug
    // in current sdkmanager/AGP tooling (installs as "android-37.0", which
    // AGP then can't resolve as target hash "android-37"), so compileSdk 37
    // is not usable yet. androidx.core:core is force-resolved to a version
    // compatible with 36 below instead of bumping compileSdk.
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires this — it uses java.time
        // APIs that need desugaring to run on API levels below 26.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Base application ID — each flavor below adds its own suffix so
        // all three can be installed side by side on the same device.
        applicationId = "co.wslha.wslha_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Three installable apps from one codebase — pair with `--flavor <name>
    // -t lib/main_<name>.dart` (see README.md). Each gets its own
    // application ID (so all three can be installed at once on one device
    // during testing) and display name (via the AndroidManifest.xml
    // `${appName}` placeholder).
    flavorDimensions += "app"
    productFlavors {
        create("customer") {
            dimension = "app"
            manifestPlaceholders["appName"] = "وصّلها"
        }
        create("driver") {
            dimension = "app"
            applicationIdSuffix = ".driver"
            manifestPlaceholders["appName"] = "وصّلها سائق"
        }
        create("merchant") {
            dimension = "app"
            applicationIdSuffix = ".merchant"
            manifestPlaceholders["appName"] = "وصّلها تاجر"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// androidx.core:core resolves to 1.19.0 transitively (via a Flutter plugin),
// which requires compileSdk 37+. Pin it back to a version compatible with
// compileSdk 36 instead of bumping compileSdk (see note above).
configurations.all {
    resolutionStrategy {
        force("androidx.core:core:1.13.1")
        force("androidx.core:core-ktx:1.13.1")
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required alongside isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
