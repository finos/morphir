import $meta._
import os.Path
import mill._, mill.scalalib._, mill.scalajslib._, scalafmt._
import com.carlosedp.aliases._
import io.eleven19.mill.crossbuild._
import org.finos.morphir.build._
import org.finos.morphir.build.elm._

object Settings {}

//-----------------------------------------------------------------------------------------------
/// Aliases that can be used to simplify and perform common commands
object MorphirAliases extends Aliases {
  @inline def lint = checkfmt
  def fmt          = alias("mill.scalalib.scalafmt.ScalafmtModule/reformatAll __.sources", "finos.morphir.elmFormat")
  def fmtScala     = alias("mill.scalalib.scalafmt.ScalafmtModule/reformatAll __.sources")
  def checkfmt     = alias("mill.scalalib.scalafmt.ScalafmtModule/checkFormatAll __.sources")
  def test         = alias("morphir.__.test")
  def testApps     = alias("morphir.cli.test", "morphir.elm.test")
  def testModules  = alias("morphir.core.__.test", "morphir.jvm.test")
}

//-----------------------------------------------------------------------------------------------
// Modules and Tasks
//-----------------------------------------------------------------------------------------------
object morphir extends CrossPlatform { root =>
  // ---------------------------------------------------------------------------------------------
  // Shared
  // ---------------------------------------------------------------------------------------------
  trait MorphirScalaCliProject extends ScalaNativeImageExecutableModule with MorphirApplicationPublishModule {
    def sources = super.sources() ++ Seq(T.workspace / "morphir" / "shared" / "cli" / "src").map(PathRef(_))

    def ivyDeps: T[Agg[Dep]] = super.ivyDeps() ++ Agg(
      ivy"com.lihaoyi::os-lib::${V.oslib}",
      ivy"com.lihaoyi::pprint::${V.pprint}",
      ivy"com.github.alexarchambault::case-app:${V.`case-app`}",
      ivy"dev.dirs:directories:${V.`directories-jvm`}",
      ivy"io.getkyo::kyo-core::${V.kyo}",
      ivy"io.getkyo::kyo-combinators::${V.kyo}",
      ivy"io.getkyo::kyo-direct::${V.kyo}",
      ivy"io.getkyo::kyo-sttp::${V.kyo}",
      ivy"org.scalameta::metaconfig-core::${V.metaconfig}",
      ivy"org.scalameta::metaconfig-sconfig::${V.metaconfig}",
      ivy"io.github.kitlangton::neotype::${V.neotype}",
      ivy"org.graalvm.polyglot:js:${V.`graal-polyglot`}",
      ivy"com.github.losizm::t2:${V.t2}"
    )
  }

  trait MorphirTests extends JavaModule with MorphirTestModule {
    def sources = super.sources() ++ Seq(T.workspace / "morphir" / "shared" / "testing" / "src").map(PathRef(_))
  }

  // ---------------------------------------------------------------------------------------------
  // CLI projects
  // ---------------------------------------------------------------------------------------------

  /// Build for the morphir/morphir-cli project
  object cli extends MorphirScalaCliProject {
    def mainClass = T {
      val className = nativeImageMainClass()
      Option(className)
    }

    def ivyDeps = super.ivyDeps() ++ Agg()

    override def moduleDeps  = Seq(morphir.jvm, morphir.core.jvm)
    def nativeImageName      = "morphir-cli" // TODO: Rename to morphir
    def nativeImageMainClass = T("org.finos.morphir.cli.Main")

    object test extends ScalaTests with MorphirTests {}
  }

  /// Build for the morphir-elm/morphir-elm-cli project
  object elm extends MorphirScalaCliProject {
    def mainClass = T {
      val className = nativeImageMainClass()
      Option(className)
    }

    def ivyDeps = super.ivyDeps() ++ Agg()

    def moduleDeps = Seq(morphir.jvm, morphir.core.jvm, morphir.lang.elm.jvm)

    def nativeImageName      = "morphir-elm-cli" // TODO: Rename to morphir-elm
    def nativeImageMainClass = T("org.finos.morphir.elm.cli.Main")
    object test extends ScalaTests with MorphirTests {}

  }

  // ---------------------------------------------------------------------------------------------
  // Libraries and Language Bindings
  // ---------------------------------------------------------------------------------------------
  /// Shared module for the morphir project
  trait Shared extends ScalaLibraryModule with PlatformAwareScalaProject with MorphirLibraryPublishModule {
    def scalaVersion = V.Scala.scala3_5_version
    def ivyDeps = Agg(
      ivy"com.lihaoyi::os-lib::${V.oslib}",
      ivy"com.github.j-mie6::parsley:${V.parsley}",
      ivy"com.github.plokhotnyuk.jsoniter-scala::jsoniter-scala-core:${V.`jsoniter-scala`}",
      ivy"com.outr::scribe::${V.scribe}",
      ivy"io.bullet::borer-core:${V.borer}",
      ivy"io.bullet::borer-derivation:${V.borer}",
      ivy"io.getkyo::kyo-core::${V.kyo}",
      ivy"io.getkyo::kyo-combinators::${V.kyo}",
      ivy"io.getkyo::kyo-direct::${V.kyo}",
      ivy"io.github.kitlangton::neotype::${V.neotype}",
      ivy"io.github.kitlangton::neotype-jsoniter:0.3.5",
      ivy"io.github.iltotore::iron:${V.iron}",
      ivy"io.kevinlee::just-semver::${V.`just-semver`}",
      ivy"org.scalameta::metaconfig-core::${V.metaconfig}",
      ivy"org.scalameta::metaconfig-sconfig::${V.metaconfig}"
    )

    def compileIvyDeps = Agg(
      ivy"com.github.plokhotnyuk.jsoniter-scala::jsoniter-scala-macros:${V.`jsoniter-scala`}"
    )

    override def platformModuleDeps: Seq[CrossPlatform] = Seq(core)
  }

  object jvm extends ScalaJvmProject with Shared {
    override def ivyDeps = super.ivyDeps() ++ Agg(
      ivy"dev.dirs:directories:${V.`directories-jvm`}"
    )
    object test extends ScalaTests with MorphirTests {
      def ivyDeps = super.ivyDeps() ++ Agg(
        ivy"io.github.kitlangton::neotype-jsoniter:0.3.5",
        ivy"com.github.plokhotnyuk.jsoniter-scala::jsoniter-scala-macros:${V.`jsoniter-scala`}"
      )
    }
  }

  object core extends CrossPlatform {
    trait Shared extends ScalaLibraryModule with PlatformAwareScalaProject with MorphirLibraryPublishModule {
      def scalaVersion = V.Scala.scala3LTSVersion
      def ivyDeps = Agg(
        ivy"org.typelevel::cats-core::${V.cats}",
        ivy"com.github.plokhotnyuk.jsoniter-scala::jsoniter-scala-core:${V.`jsoniter-scala`}"
      )

      def compileIvyDeps = Agg(
        ivy"com.github.plokhotnyuk.jsoniter-scala::jsoniter-scala-macros:${V.`jsoniter-scala`}"
      )
    }

    object jvm extends ScalaJvmProject with Shared {
      override def ivyDeps: Target[Agg[Dep]] = super.ivyDeps() ++ Agg(
        ivy"dev.dirs:directories:${V.`directories-jvm`}"
      )
      object test extends ScalaTests with MorphirTests {
        def ivyDeps = super.ivyDeps() ++ Agg(
          ivy"com.lihaoyi::os-lib::${V.oslib}"
        )
        def scalaVersion = V.Scala.scala3_5_version
      }
    }
  }

  object lang extends Module {
    object elm extends CrossPlatform {
      trait Shared extends ScalaLibraryModule with PlatformAwareScalaProject with MorphirLibraryPublishModule {
        def scalaVersion = V.Scala.scala3_5_version
        def ivyDeps = Agg(
          ivy"com.outr::scribe::${V.scribe}",
          ivy"io.getkyo::kyo-core::${V.kyo}",
          ivy"io.github.iltotore::iron:${V.iron}"
        )
        override def platformModuleDeps: Seq[CrossPlatform] = Seq(morphir.core)
      }

      object jvm extends ScalaJvmProject with Shared {
        def ivyDeps = Agg(
          ivy"org.typelevel::cats-core::${V.cats}"
        )
        def moduleDeps = Seq(morphir.jvm)
        object test extends ScalaTests with MorphirTests {}
      }
    }
  }
}

//---------------------------------------------------------------------------------------------
// Elm Ecosystem Projects
//---------------------------------------------------------------------------------------------
object finos extends Module {

  /// This is the build for the finos/morphir Elm project, which previously was finos/morphir-elm
  /// in the Elm package manager.
  /// Elm's publishing requirements for packages require the source code to be a subdirectory
  /// of the src folder at the root of the project.
  object morphir extends ElmModule with ElmFormatModule {
    override def millSourcePath: Path = super.millSourcePath / os.up / os.up
  }
}
