import $meta._
import mill._, mill.scalalib._, mill.scalajslib._, scalafmt._
import com.carlosedp.aliases._
import io.eleven19.mill.crossbuild._
import org.finos.morphir.build._


object Settings {}

object Deps {}

object V {

  val `case-app`       = "2.1.0-M29"
  val kyo              = "0.11.0"
  val oslib            = "0.10.4"
  val pprint           = "0.9.0"
  val neotype          = "0.3.0"
  val `scala-uri`      = "4.0.3"
  val `graal-polyglot` = "24.0.2"

  object Scala {
    val libraryScalaVersion    = "3.3.3"
    val executableScalaVersion = "3.5.0"
  }

  object ScalaJS {
    val scalaJsVersion = "1.16.0"
  }
}

trait CommonScalaModule extends ScalaModule with ScalafmtModule {
  def scalaVersion = V.Scala.libraryScalaVersion
}

trait ScalaExecutableModule extends CommonScalaModule {
  def scalaVersion = V.Scala.executableScalaVersion
}

trait ScalaLibraryModule extends CommonScalaModule {
  def scalaVersion = V.Scala.libraryScalaVersion
}

trait MorphirPublishModule extends PubMod {
  override def customVersionTag: T[Option[String]] = T(Some("0.0.0"))
}

object root extends RootModule {

  object MorphirAliases extends Aliases {
    @inline def lint = checkfmt
    def fmt           = alias("mill.scalalib.scalafmt.ScalafmtModule/reformatAll __.sources")
    def checkfmt      = alias("mill.scalalib.scalafmt.ScalafmtModule/checkFormatAll __.sources")
  }
  object apps extends Module {
    object cli extends ScalaExecutableModule with NativeImageDefaults with MorphirPublishModule {
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
    }
  }

  object modules extends Module {
    object scala extends Module {
      object codemodel extends CrossPlatform {
        trait Shared extends ScalaLibraryModule with PlatformAwareScalaProject with MorphirPublishModule {
          def artifactNameParts = Seq("morphir", "codemodel")
        }
        object jvm extends ScalaJvmProject with Shared {}
      }
    }
  }
}
