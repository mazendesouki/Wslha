plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "co.wslha.wslha_app"
    // Pinned to 37 (not flutter.compileSdkVersion) — androidx.core:core:1.19.0
    // (pulled in transitively by plugins like shared_preferences) requires
    // compileSdk 37+; the Flutter-default SDK level was still 36.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
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

flutter {
    source = "../.."
}
