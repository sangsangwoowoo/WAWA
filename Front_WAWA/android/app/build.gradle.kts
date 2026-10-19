import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.songhyoeun.learningapp"
    compileSdk = findProperty("flutter.compileSdkVersion")?.toString()?.toInt() ?: 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.songhyoeun.learningapp"
        minSdk = 24
        targetSdk = findProperty("flutter.targetSdkVersion")?.toString()?.toInt() ?: 36
        versionCode = findProperty("flutter.versionCode")?.toString()?.toInt() ?: 1
        versionName = findProperty("flutter.versionName")?.toString() ?: "1.0.0"
        manifestPlaceholders["appAuthRedirectScheme"] = "com.songhyoeun.learningapp"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = file(keystoreProperties["storeFile"] as String?)
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true       // 코드 축소 활성화 필수
            isShrinkResources = true     // 리소스 축소 활성화

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}