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
// Some plugins (e.g. flutter_blue_plus) compile against old SDKs, but their
// AndroidX dependencies require compileSdk 34+.
subprojects {
    if (name != "app") {
        afterEvaluate {
            extensions.findByName("android")?.let { android ->
                val current = android.javaClass.getMethod("getCompileSdk").invoke(android) as Int?
                if (current == null || current < 36) {
                    android.javaClass.getMethod("setCompileSdk", Integer::class.java).invoke(android, 36)
                }
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
