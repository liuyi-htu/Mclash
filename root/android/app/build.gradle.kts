import java.util.Properties
import org.gradle.api.tasks.bundling.Zip

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

val signingEnvironmentNames = mapOf(
    "storeFile" to "MCLASH_STORE_FILE",
    "storePassword" to "MCLASH_STORE_PASSWORD",
    "keyAlias" to "MCLASH_KEY_ALIAS",
    "keyPassword" to "MCLASH_KEY_PASSWORD",
)

fun releaseSigningProperty(name: String): String =
    releaseKeyProperties.getProperty(name)?.trim()
        ?.takeIf(String::isNotEmpty)
        ?: System.getenv(signingEnvironmentNames.getValue(name))?.trim().orEmpty()

val releaseStoreFilePath = releaseSigningProperty("storeFile")
val releaseStoreFile = releaseStoreFilePath.takeIf { it.isNotEmpty() }?.let(rootProject::file)
val hasReleaseSigning =
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

            // Keep native integration predictable for release builds.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

val packageRootModule by tasks.registering(Zip::class) {
    group = "build"
    description = "Packages the installable Mclash Root module into APK assets."
    from(rootProject.projectDir.parentFile.resolve("root-module"))
    archiveFileName.set("mclash_root.zip")
    destinationDirectory.set(layout.buildDirectory.dir("generated/rootAssets/root"))
    // Root 模块必须每次从当前源码重新打包，不复用上次产物。
    outputs.upToDateWhen { false }
    doFirst {
        archiveFile.get().asFile.delete()
    }
}

android.sourceSets.getByName("main").assets.srcDir(
    layout.buildDirectory.dir("generated/rootAssets"),
)
tasks.named("preBuild").configure { dependsOn(packageRootModule) }

flutter {
    source = "../.."
}


dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
}
