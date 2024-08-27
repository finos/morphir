import $meta._
import mill._, mill.scalalib._, mill.scalajslib._, scalafmt._
import com.carlosedp.aliases._
import io.eleven19.mill.crossbuild._
import org.finos.morphir.build._

object Settings {}

  //-----------------------------------------------------------------------------------------------
  /// Aliases that can be used to simplify and perform common commands
  object MorphirAliases extends Aliases {
    @inline def lint = checkfmt
    def fmt           = alias("mill.scalalib.scalafmt.ScalafmtModule/reformatAll __.sources")
    def checkfmt      = alias("mill.scalalib.scalafmt.ScalafmtModule/checkFormatAll __.sources")
    def testApps      = alias("apps.__.test")
    def testModules   = alias("apps.__.test")
  }



trait CommonScalaModule extends ScalaModule with ScalafmtModule with MorphirBaseProject {
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

trait MorphirLibraryPublishModule extends MorphirPublishModule {
  def publishLibraryArtifacts = T { publishArtifacts() }
}

trait MorphirApplicationPublishModule extends MorphirPublishModule {
  def publishApplicationArtifacts = T { publishArtifacts()}
}