import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties, which is gitignored.
// See android/key.properties.example.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseSigning = keystorePropertiesFile.exists()

android {
    namespace = "com.example.vaultx"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // NOTE: still the Flutter template placeholder. Change this to a domain
        // you control before publishing — but be aware that changing it makes
        // an existing install a different app, so users lose their vault.
        applicationId = "com.example.vaultx"
        // 26 is required for the hardware-backed, auth-bound Keystore key used
        // by DeviceKeyChannel. StrongBox (28+) is used opportunistically.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // v3 signed release builds with the debug keystore. Debug keys are
            // public and identical on every machine, so anyone could forge an
            // update that Android would accept as genuine. Real keys now come
            // from key.properties; without it the build stays on debug keys and
            // warns loudly rather than silently shipping something installable.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

if (!hasReleaseSigning) {
    gradle.taskGraph.whenReady {
        if (allTasks.any { it.name.contains("Release", ignoreCase = true) }) {
            logger.warn(
                "\n*** VaultX: android/key.properties not found. This release build is " +
                    "signed with the PUBLIC debug key and must not be distributed. " +
                    "See android/key.properties.example. ***\n"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Binds biometric authentication to the Keystore cipher via CryptoObject.
    implementation("androidx.biometric:biometric:1.1.0")
}
