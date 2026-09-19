import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload/release signing credentials live in android/key.properties, which is
// gitignored along with the keystore it points at. Neither is ever committed.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
var keystorePropertiesReadable = true
if (keystorePropertiesFile.exists()) {
    try {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    } catch (_: Exception) {
        keystorePropertiesReadable = false
    }
}

val requiredReleaseSigningProperties = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val missingReleaseSigningProperties = requiredReleaseSigningProperties.filter { name ->
    keystoreProperties.getProperty(name)?.trim().isNullOrEmpty()
}
val releaseKeystoreFile = keystoreProperties
    .getProperty("storeFile")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
    ?.let { file(it) }

val releaseSigningProblem = when {
    !keystorePropertiesFile.exists() ->
        "android/key.properties is missing."
    !keystorePropertiesReadable ->
        "android/key.properties could not be read."
    missingReleaseSigningProperties.isNotEmpty() ->
        "android/key.properties is missing required properties: " +
            missingReleaseSigningProperties.joinToString(", ") + "."
    releaseKeystoreFile?.isFile != true ->
        "The keystore file referenced by storeFile in android/key.properties does not exist."
    else -> null
}

val releaseArtifactTaskNames = setOf(
    "assembleRelease",
    "bundleRelease",
    "packageRelease",
    "signReleaseBundle",
)

// Validate only task graphs that produce a release artifact. Debug builds do
// not need access to upload credentials, while every release APK/AAB must stop
// before execution if the upload signing configuration is unavailable.
gradle.taskGraph.whenReady {
    val buildsReleaseArtifact = allTasks.any { task ->
        task.project == project && task.name in releaseArtifactTaskNames
    }
    if (buildsReleaseArtifact && releaseSigningProblem != null) {
        throw GradleException(
            "Release build stopped: $releaseSigningProblem " +
                "No release APK/AAB was produced, and debug signing was not used."
        )
    }
}

android {
    namespace = "com.azim.nutriscan"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.azim.nutriscan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningProblem == null) {
                // storeFile is resolved relative to this module (android/app).
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningProblem == null) {
                signingConfig = signingConfigs.getByName("release")
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
