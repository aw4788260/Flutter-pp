allprojects {
    repositories {
        // ✅ ترتيب المستودعات (يفضل وضع البوابة أولاً)
        gradlePluginPortal()
        google()
        mavenCentral()
    }

    // ✅ الحل الجذري: إجبار Gradle على استخدام نسخة LTS المتاحة
    configurations.all {
        resolutionStrategy {
            eachDependency {
                // إجبار النظام على استخدام نسخة LTS المستقرة والموجودة فعلياً في Maven Central
                if (requested.group == "com.arthenica" && 
                    requested.name.contains("ffmpeg-kit") && 
                    requested.version == "6.0-3") {
                    
                    useVersion("6.0-3.LTS")
                    because("The non-LTS version 6.0-3 is missing from Maven Central, forcing stable LTS version.")
                }
            }
        }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
