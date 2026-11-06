pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.5.1" apply false
    // Resolve KGP before AGP enters the settings plugin classloader; do not apply it.
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
}

include(":app")


// Pinned plugin migrations for AGP 9 built-in Kotlin. Never edit shared pub cache.
fun useMigratedPluginBuild(name: String, version: String, expectedHash: String) {
    val plugin = project(":$name")
    require(plugin.projectDir.parentFile.name == "$name-$version") {
        "Re-audit the $name AGP override when changing versions."
    }
    val upstream = java.io.File(plugin.projectDir, "build.gradle")
    val actualHash = java.security.MessageDigest.getInstance("SHA-256")
        .digest(upstream.readBytes()).joinToString("") { "%02x".format(it) }
    require(actualHash == expectedHash) {
        "$name Android build script changed; re-audit before building."
    }
    plugin.buildFileName = plugin.projectDir.toPath()
        .relativize(file("compat/$name.gradle").toPath()).toString()
}

useMigratedPluginBuild("flutter_tts", "4.2.5", "e8282fed47a650a28c490df7cae3c800db574b8335a7d4d2b8db806378482088")
useMigratedPluginBuild("home_widget", "0.10.0", "c8ec7ffe5b27a41ad980d5a87c117ac7deec1fa72b63f9294535bdaedef0924e")
