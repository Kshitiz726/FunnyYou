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
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Pin every Android module to compileSdk 36.
//
// The toolchain otherwise resolves `android-37`, which the SDK manager
// installs into a folder named `android-37.0` — Gradle looks for `android-37`
// and fails. 36 is installed and every plugin here compiles against it.
//
// Must be registered before the `evaluationDependsOn` block below, which
// forces subprojects to evaluate immediately.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            when (android) {
                is com.android.build.gradle.LibraryExtension ->
                    android.compileSdk = 36
                is com.android.build.gradle.AppExtension ->
                    android.compileSdkVersion(36)
                else -> {}
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
