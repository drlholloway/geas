allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Every Android dependency is held to the version in gradle.lockfile, here
// and in app/, so a build can't silently pick up a different one. To change
// them (a new plugin, a new Flutter), run from this directory:
//   ./gradlew dependencies :app:dependencies --write-locks
// and commit both lock files. This project has no dependencies of its own,
// so its gradle.lockfile says only that; the app's holds them all.
dependencyLocking {
    lockAllConfigurations()
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
