buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Use the same Kotlin compiler for app and plugin code under AGP built-in Kotlin.
        val kotlinVersion = providers.gradleProperty("neuraKotlinPluginVersion").get()
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // Some Flutter plugins declare old buildscript toolchains even though the
    // app already provides AGP and Kotlin. Constraints only affect modules
    // present on the build classpath; they add no app runtime dependencies.
    val androidVersion = providers.gradleProperty("neuraAndroidPluginVersion").get()
    val kotlinVersion = providers.gradleProperty("neuraKotlinPluginVersion").get()
    buildscript.dependencies.constraints {
        add("classpath", "com.android.tools.build:gradle:$androidVersion")
        add("classpath", "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
        // Minimum fixes for advisories in plugin build tooling. Keep these off
        // the app runtime classpath; Gradle can select newer compatible versions.
        add("classpath", "com.google.guava:guava:33.7.2-jre")
        add("classpath", "org.apache.commons:commons-lang3:3.18.0")
        add("classpath", "org.bitbucket.b_c:jose4j:0.9.6")
        add("classpath", "org.bouncycastle:bcpkix-jdk18on:1.85")
        add("classpath", "org.bouncycastle:bcprov-jdk18on:1.85")
        add("classpath", "org.jdom:jdom2:2.0.6.1")
    }
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
