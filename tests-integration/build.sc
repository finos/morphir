// build.sc
import mill._, scalalib._

object generated extends Module {
  object refModel extends ScalaModule {
    def scalaVersion = "2.11.12"
    def ivyDeps = Agg(ivy"org.morphir::morphir-sdk-core:0.6.1")
  }
}
