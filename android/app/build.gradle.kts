import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing — three sources, in priority order:
//   1. CI (GitHub Actions): KEYSTORE_FILE / KEYSTORE_PASSWORD / KEY_ALIAS /
//      KEY_PASSWORD environment variables (decoded from repo secrets — see
//      README "Release signing in CI").
//   2. Local: android/key.properties next to this file (gitignored) holding
//      storeFile / storePassword / keyAlias / keyPassword.
//   3. Fallback: debug signing so `flutter run --release` and CI artifact
//      builds always work before a real keystore is configured.
// ---------------------------------------------------------------------------
val keystorePropertiesFile: File = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun releaseKeystoreFile(): File? {
    val envPath: String? = System.getenv("KEYSTORE_FILE")
    if (envPath != null && File(envPath).exists()) return File(envPath)
    val local: String? = keystoreProperties.getProperty("storeFile")
    if (local != null) {
        val f = File(local)
        if (f.isAbsolute && f.exists()) return f
        val relative = rootProject.file(local)
        if (relative.exists()) return relative
    }
    return null
}

android {
    namespace = "com.muktibeg.freescanner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.muktibeg.freescanner"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (releaseKeystoreFile() != null) {
        signingConfigs {
            create("release") {
                storeFile = releaseKeystoreFile()
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                    ?: keystoreProperties.getProperty("storePassword")
                keyAlias = System.getenv("KEY_ALIAS")
                    ?: keystoreProperties.getProperty("keyAlias")
                keyPassword = System.getenv("KEY_PASSWORD")
                    ?: keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Real upload key when available (CI secrets or key.properties),
            // debug signing otherwise (installable, but not for Play upload).
            signingConfig = if (releaseKeystoreFile() != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
