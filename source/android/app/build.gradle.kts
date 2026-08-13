import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseKeyProperties = Properties()

if (releaseKeyPropertiesFile.isFile) {
    releaseKeyPropertiesFile.inputStream().use(releaseKeyProperties::load)
}

fun releaseSigningProperty(name: String): String =
    releaseKeyProperties.getProperty(name)?.trim().orEmpty()

val releaseStoreFilePath = releaseSigningProperty("storeFile")
val releaseStoreFile = releaseStoreFilePath.takeIf { it.isNotEmpty() }?.let(rootProject::file)
val hasReleaseSigning =
    releaseKeyPropertiesFile.isFile &&
        releaseStoreFile?.isFile == true &&
        releaseSigningProperty("storePassword").isNotEmpty() &&
        releaseSigningProperty("keyAlias").isNotEmpty() &&
        releaseSigningProperty("keyPassword").isNotEmpty()

if (releaseKeyPropertiesFile.isFile && !hasReleaseSigning) {
    logger.lifecycle(
        "Release signing config is incomplete or storeFile is missing; building an unsigned release APK.",
    )
}

android {
    namespace = "com.liuyihtu.mclash"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.2.12479018"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.liuyihtu.mclash"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseSigningProperty("storePassword")
                keyAlias = releaseSigningProperty("keyAlias")
                keyPassword = releaseSigningProperty("keyPassword")
            }
        }
    }

    packaging {
        jniLibs {
            // The official mihomo executable is packaged as libmihomo.so so Android
            // extracts it into applicationInfo.nativeLibraryDir with execute permission.
            useLegacyPackaging = true
            keepDebugSymbols += setOf("**/libmihomo.so")
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }

            // Hev registers JNI methods by exact name. Disable shrinking for
            // this minimal diagnostic build and also keep explicit rules.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}


dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
}
