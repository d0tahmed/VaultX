allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// SECURE NAMESPACE FIX - Now placed BEFORE the lock!
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (androidExt != null && androidExt.namespace.isNullOrEmpty()) {
            androidExt.namespace = project.group.toString()
        }
    }
}

// The Lock
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}