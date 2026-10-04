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
    id("com.android.application") version "9.1.0" apply false
    // Resolve KGP before AGP enters the settings plugin classloader; do not apply it.
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")


// file_picker 10.3.10 predates AGP built-in Kotlin. Keep its package sources
// untouched and replace only its Android build script with a reviewed migration.
val filePicker = project(":file_picker")
require(filePicker.projectDir.parentFile.name == "file_picker-10.3.10") {
    "Re-audit the file_picker AGP compatibility override when changing versions."
}
val upstreamBuild = java.io.File(filePicker.projectDir, "build.gradle")
val upstreamSha256 = java.security.MessageDigest.getInstance("SHA-256")
    .digest(upstreamBuild.readBytes()).joinToString("") { "%02x".format(it) }
require(upstreamSha256 == "79ce53fe53d18bfa809671f08828c5d5a6bfb62ce30af6e5c4a2496f0a0ad3ea") {
    "file_picker Android build script changed; re-audit before building."
}
filePicker.buildFileName = filePicker.projectDir.toPath()
    .relativize(file("compat/file_picker.gradle").toPath()).toString()
