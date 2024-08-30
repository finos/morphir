import os.Path
import $meta._
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
  def fmt           = alias("mill.scalalib.scalafmt.ScalafmtModule/reformatAll __.sources", "finos.morphir.elmFormat")
  def checkfmt      = alias("mill.scalalib.scalafmt.ScalafmtModule/checkFormatAll __.sources")
  def testApps      = alias("apps.__.test")
  def testModules   = alias("apps.__.test")
}


//-----------------------------------------------------------------------------------------------
// Modules and Tasks
//-----------------------------------------------------------------------------------------------
object morphir extends Module {
  //---------------------------------------------------------------------------------------------
  // Shared
  //---------------------------------------------------------------------------------------------
  trait MorphirScalaCliProject extends ScalaNativeImageExecutableModule with MorphirApplicationPublishModule {  
    def sources = super.sources() ++ Seq(T.workspace / "morphir" / "shared" / "cli" / "src").map(PathRef(_))

    def ivyDeps: T[Agg[Dep]] = super.ivyDeps() ++ Agg(
      ivy"com.lihaoyi::os-lib::${V.oslib}",
      ivy"com.lihaoyi::pprint::${V.pprint}",
      ivy"com.github.alexarchambault::case-app:${V.`case-app`}",
      ivy"io.getkyo::kyo-core::${V.kyo}",
      ivy"io.getkyo::kyo-direct::${V.kyo}",
      ivy"io.getkyo::kyo-sttp::${V.kyo}",
      ivy"io.github.kitlangton::neotype::${V.neotype}",
      ivy"org.graalvm.polyglot:js:${V.`graal-polyglot`}"
    )
  }

  trait MorphirTests extends JavaModule with MorphirTestModule { 
    def sources = super.sources() ++ Seq(T.workspace / "morphir" / "shared" / "testing" / "src").map(PathRef(_))
  }

  //---------------------------------------------------------------------------------------------
  // CLI projects
  //---------------------------------------------------------------------------------------------


  /// Build for the morphir/morphir-cli project
  object cli extends MorphirScalaCliProject {    
    def mainClass = T {
      val className = nativeImageMainClass()
      Option(className)
    }

    def ivyDeps = super.ivyDeps() ++ Agg() 

    override def moduleDeps = Seq(scalalib.jvm)
    def nativeImageName      = "morphir-cli" // TODO: Rename to morphir
    def nativeImageMainClass = T("org.finos.morphir.cli.Main")


    object test extends ScalaTests with TestModule.ScalaTest {
      def ivyDeps = Agg(
        ivy"org.scalatest::scalatest:${V.scalatest}"
      )
    }
  } 

  /// Build for the morphir-elm/morphir-elm-cli project
  object elm extends MorphirScalaCliProject {
    def mainClass = T {
      val className = nativeImageMainClass()
      Option(className)
    }

    def ivyDeps = super.ivyDeps() ++ Agg()

    def moduleDeps = Seq(scalalib.jvm)

    def nativeImageName = "morphir-elm-cli" //TODO: Rename to morphir-elm
    def nativeImageMainClass = T("org.finos.morphir.elm.cli.Main")
  }

  //---------------------------------------------------------------------------------------------
  // Libraries and Language Bindings
  //---------------------------------------------------------------------------------------------
  object scalalib extends CrossPlatform {
    trait Shared extends ScalaLibraryModule with PlatformAwareScalaProject with MorphirLibraryPublishModule {   
      def scalaVersion = V.Scala.scala3_5_version       
      def ivyDeps = Agg(
        ivy"io.getkyo::kyo-core::${V.kyo}",
        ivy"io.github.kitlangton::neotype::${V.neotype}",
      )

      override def platformModuleDeps: Seq[CrossPlatform] = Seq(vfs)
    }
    object jvm extends ScalaJvmProject with Shared {
      object test extends ScalaTests with MorphirTests { }
    }

    object vfs extends CrossPlatform {
      trait Shared extends ScalaLibraryModule with PlatformAwareScalaProject with MorphirLibraryPublishModule {        
        def scalaVersion = V.Scala.scala3LTSVersion
        def ivyDeps = Agg(
          ivy"org.typelevel::cats-core::${V.cats}"
        )
      }

      object jvm extends ScalaJvmProject with Shared {
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