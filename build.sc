import $meta._
import mill._, mill.scalalib._, mill.scalajslib._, scalafmt._
import com.carlosedp.aliases._
import io.eleven19.mill.crossbuild._
import org.finos.morphir.build._
import org.finos.morphir.build.elm._

object Settings {}

object root extends RootModule with ElmModule with ElmFormatModule {

  //-----------------------------------------------------------------------------------------------
  /// Aliases that can be used to simplify and perform common commands
  object MorphirAliases extends Aliases {
    @inline def lint = checkfmt
    def fmt           = alias("mill.scalalib.scalafmt.ScalafmtModule/reformatAll __.sources")
    def checkfmt      = alias("mill.scalalib.scalafmt.ScalafmtModule/checkFormatAll __.sources")
    def testApps      = alias("apps.__.test")
    def testModules   = alias("apps.__.test")
  }

  //-----------------------------------------------------------------------------------------------
  // Modules and Tasks
  //-----------------------------------------------------------------------------------------------
  object apps extends Module {
    object cli extends ScalaNativeImageExecutableModule with MorphirApplicationPublishModule {
      override def projectNameParts: T[Seq[String]] = Seq("morphir", "cli")
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
        ivy"io.github.kitlangton::neotype::${V.neotype}",
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

  object modules extends Module {
    object scalalang extends Module {
      object codemodel extends CrossPlatform {
        trait Shared extends ScalaLibraryModule with PlatformAwareScalaProject with MorphirLibraryPublishModule {
          def artifactNameParts = Seq("morphir", "codemodel")
        }
        object jvm extends ScalaJvmProject with Shared {
          object test extends ScalaTests with TestModule.ScalaTest {
            def ivyDeps = Agg(
              ivy"org.scalatest::scalatest::3.2.19"
            )
          }
        }
      }
    }
  }
}


