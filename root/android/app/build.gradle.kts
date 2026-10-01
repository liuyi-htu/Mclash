import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localSigningProperties = rootProject.file("key.properties")
val sharedSigningProperties = rootProject.projectDir.parentFile.parentFile.parentFile
    .resolve("signing/key.properties")
val releaseKeyPropertiesFile = System.getenv("MCLASH_SIGNING_PROPERTIES")
    ?.takeIf(String::isNotBlank)?.let(::File)
    ?: localSigningProperties.takeIf { it.isFile }
    ?: sharedSigningProperties
val releaseKeyProperties = Properties()

if (releaseKeyPropertiesFile.isFile) {
    releaseKeyPropertiesFile.inputStream().use(releaseKeyProperties::load)
}

fun releaseSigningProperty(name: String): String =
    releaseKeyProperties.getProperty(name)?.trim().orEmpty()

val releaseStoreFilePath = releaseSigningProperty("storeFile")
val releaseStoreFile = releaseStoreFilePath.takeIf { it.isNotEmpty() }?.let { path ->
    val configured = File(path)
    val primary = if (configured.isAbsolute) configured
        else if (releaseKeyPropertiesFile == localSigningProperties) rootProject.file(path)
        else releaseKeyPropertiesFile.parentFile.resolve(path)
    // Shared properties may retain a path from the original build machine.
    // Reuse only the identically named keystore beside those properties.
    if (primary.isFile || releaseKeyPropertiesFile == localSigningProperties) primary
    else releaseKeyPropertiesFile.parentFile.resolve(configured.name)
}
val hasReleaseSigning =
    releaseKeyPropertiesFile.isFile &&
        releaseStoreFile?.isFile == true &&
        releaseSigningProperty("storePassword").isNotEmpty() &&
        releaseSigningProperty("keyAlias").isNotEmpty() &&
        releaseSigningProperty("keyPassword").isNotEmpty()

val requestsReleaseBuild = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
check(!requestsReleaseBuild || hasReleaseSigning) {
    "Root release APK requires complete release signing properties and an existing keystore."
}

android {
    namespace = "com.liuyihtu.mclash.root"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.2.12479018"

    sourceSets.getByName("main").assets.srcDir(
        rootProject.projectDir.parentFile.parentFile.resolve("assets"),
    )

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.liuyihtu.mclash.root"
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

            // Keep the Root process and diagnostics easy to inspect.
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
    implementation("org.yaml:snakeyaml:2.7")
    testImplementation("junit:junit:4.13.2")
}
