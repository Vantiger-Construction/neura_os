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

useMigratedPluginBuild("file_picker", "10.3.10", "79ce53fe53d18bfa809671f08828c5d5a6bfb62ce30af6e5c4a2496f0a0ad3ea")
useMigratedPluginBuild("flutter_tts", "4.2.5", "e8282fed47a650a28c490df7cae3c800db574b8335a7d4d2b8db806378482088")
useMigratedPluginBuild("home_widget", "0.7.0+1", "e1d938fcf429fd0ac49a45361be1b12025d8a4dc4cbfdd24c455f9df431e5e75")
useMigratedPluginBuild("record_android", "1.5.2", "dcba04d15702fa261bf1b078b1e82aaa4d07e18c21f5a6677359a926861dce5a")
useMigratedPluginBuild("share_plus", "7.2.2", "63e6a6a3e864d08dad93c814cb109416af61141b3713aa64691a1e7ebf2c3bf0")
useMigratedPluginBuild("speech_to_text", "7.4.0", "df104306878240f8e445b42913ccc6abb471e87f9fcc917594e76a5d8592e635")
