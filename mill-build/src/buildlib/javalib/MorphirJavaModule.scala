package buildlib.javalib
import mill.*
import mill.scalalib.*

trait MorphirJavaModule extends JavaModule:
    def jvmIndexVersion = "latest.release"
