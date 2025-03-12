import org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi

plugins{
    alias(libs.plugins.kotlin.multiplatform)
}

kotlin {
    jvmToolchain(21)
    jvm{
        @OptIn(ExperimentalKotlinGradlePluginApi::class)
        binaries {
            executable {
                mainClass.set("org.finos.morphir.cli.MainKt")
            }
        }
    }
    macosX64()
    mingwX64()
    sourceSets {
        commonMain {
            dependencies {
                implementation(libs.clikt)
                implementation(libs.clikt.markdown)
            }
        }
    }
}