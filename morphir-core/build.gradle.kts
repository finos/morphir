plugins{
    alias(libs.plugins.kotlin.multiplatform)
}

kotlin {
    jvm()
    js{
        browser()
        nodejs()
    }
    sourceSets {
        commonMain{
            dependencies {
                implementation(libs.kotlinx.datetime)
            }
        }
        commonTest {
            dependencies {
                implementation(rootProject.libs.kotest.extensions.htmlreporter)
                implementation(rootProject.libs.kotest.extensions.junitxml)
                implementation(libs.kotest.assertions.core)
                implementation(libs.kotest.framework.engine)
                implementation(libs.kotest.property)
            }
        }
        jvmTest {
            dependencies {
                implementation(libs.kotest.runner.junit5)
            }
        }
    }
    tasks.withType<Test>().configureEach {
        useJUnitPlatform()
    }
}

val enableNodeJsDownload = (project.findProperty("kmp.nodejs.download") as String? ?: "false").toBoolean()

project.plugins.withType<org.jetbrains.kotlin.gradle.targets.js.nodejs.NodeJsPlugin> {
    logger.lifecycle("enableNodeJsDownload: $enableNodeJsDownload")

    project.extensions.getByType<org.jetbrains.kotlin.gradle.targets.js.nodejs.NodeJsEnvSpec>().apply {
        download = enableNodeJsDownload
    }
}