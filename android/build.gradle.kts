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
                // التحقق من الحزمة المطلوبة (full-gpl) واستبدال الإصدار المفقود
                if (requested.group == "com.arthenica" &&
                    requested.name == "ffmpeg-kit-full-gpl" &&
                    requested.version == "6.0-2") {
                    
                    useVersion("6.0-2.LTS")
                    because("Version 6.0-2 is missing from Maven Central, replaced with 6.0-2.LTS")
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
