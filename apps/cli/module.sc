import mill._, scalalib._
import io.eleven19.mill.crossbuild._
import org.finos.morphir.build._

  object apps extends RootModule with MorphirBaseProject {
    object cli extends ScalaExecutableModule with NativeImageDefaults with MorphirApplicationPublishModule {
      override def artifactNameParts: T[Seq[String]] = Seq("morphir", "cli")
      def mainClass = T {
        val className = nativeImageMainClass()
        Option(className)
      }

      def ivyDeps = Agg(
        ivy"com.lihaoyi::os-lib:${V.oslib}",
        ivy"com.lihaoyi::pprint:${V.pprint}",
        ivy"com.github.alexarchambault::case-app:${V.`case-app`}",
        ivy"io.getkyo::kyo-core:${V.kyo}",
        ivy"io.getkyo::kyo-direct:${V.kyo}",
        ivy"io.getkyo::kyo-sttp:${V.kyo}",
        ivy"org.graalvm.polyglot:js:${V.`graal-polyglot`}"
      )
      def nativeImageName      = "morphir-cli" // TODO: Rename to morphir
      def nativeImageMainClass = T("org.finos.morphir.cli.Main")


      object test extends ScalaTests with TestModule.ScalaTest {
        def ivyDeps = Agg(
          ivy"org.scalatest::scalatest:${V.scalatest}"
        )
      }
    }
  }