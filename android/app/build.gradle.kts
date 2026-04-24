plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ktlint)
}

android {
    namespace = "com.inkbridge.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.inkbridge.app"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.0.1-foundation"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    // Use JUnit Platform for JUnit 5 support
    testOptions {
        unitTests.all {
            it.useJUnitPlatform()
        }
    }
}

// ── Test-vector wiring ───────────────────────────────────────────────────────
// Canonical protocol vectors live in ../../protocol/test-vectors/.
// Copy them into a staging dir and expose that dir as a test resource root so
// they land on the test classpath under `vectors/<name>`.
val protocolVectorsStaging = layout.buildDirectory.dir("generated/test-vectors")

val copyProtocolVectors by tasks.registering(Copy::class) {
    from(rootProject.projectDir.parentFile.resolve("protocol/test-vectors"))
    into(protocolVectorsStaging.map { it.dir("vectors") })
}

android.sourceSets.getByName("test").resources.srcDir(protocolVectorsStaging)

tasks.matching { it.name == "processDebugUnitTestJavaRes" || it.name == "mergeDebugUnitTestJavaResource" }
    .configureEach { dependsOn(copyProtocolVectors) }

dependencies {
    // Compose BOM — version pinned via catalog
    val composeBom = platform(libs.compose.bom)
    implementation(composeBom)
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.activity)
    debugImplementation(libs.compose.ui.tooling)

    // Coroutines
    implementation(libs.coroutines.android)

    // Navigation
    implementation(libs.navigation.compose)

    // ViewModel + Compose integration
    implementation(libs.lifecycle.viewmodel.compose)

    // Compose Foundation (Canvas, border, etc.)
    implementation(libs.compose.foundation)

    // Material Icons Extended (used in StatusScreen)
    implementation(libs.compose.material.icons)

    // Binary I/O (OKio — useful for codec work in Phase 1)
    implementation(libs.okio)

    // JUnit 5
    testImplementation(libs.junit5.api)
    testImplementation(libs.junit5.params)
    testRuntimeOnly(libs.junit5.engine)
    testRuntimeOnly(libs.junit5.platform.launcher)
    testImplementation(libs.coroutines.test)
}
