package org.finos.morphir.build
import mill._
import mill.scalalib._
import mill.scalalib.scalafmt._
import mill.contrib.buildinfo.BuildInfo

trait CommonModule extends Module {
  final def projectName: T[String]     = T(projectNameParts().mkString("-"))
  def projectNameParts: T[Seq[String]] = T(millModuleSegments.parts)
}

trait CommonScalaModule extends CommonModule with ScalaModule with ScalafmtModule {
  def scalaVersion = V.Scala.libraryScalaVersion
}

trait ScalaExecutableModule extends CommonScalaModule {
  def scalaVersion = V.Scala.executableScalaVersion
}

trait ScalaNativeImageExecutableModule extends ScalaExecutableModule with NativeImageDefaults {}

trait ScalaLibraryModule extends CommonScalaModule {
  def scalaVersion = V.Scala.libraryScalaVersion
}

trait MorphirPublishModule extends PubMod {
  override def customVersionTag: T[Option[String]] = T(Some("0.0.0"))
}

trait MorphirLibraryPublishModule extends MorphirPublishModule { self: CommonModule =>
  override def artifactNameParts: T[Seq[String]] = projectNameParts()
  def publishLibraryArtifacts                    = T(publishArtifacts())
}

trait MorphirApplicationPublishModule extends MorphirPublishModule with BuildInfo {
  self: CommonModule with ScalaModule =>
  val buildInfoPackageName                       = "org.finos.morphir.build"
  override def artifactNameParts: T[Seq[String]] = projectNameParts()
  def publishApplicationArtifacts                = T(publishArtifacts())
  def buildInfoMembers = Seq(
    BuildInfo.Value("scalaVersion", scalaVersion()),
    BuildInfo.Value("version", publishVersion()),
    BuildInfo.Value("buildTime", java.time.Instant.now.toString)
  )
}

trait MorphirTestModule extends TestModule.ZioTest {
  def ivyDeps = super.ivyDeps() ++ Agg(
    ivy"com.lihaoyi::os-lib:${V.oslib}",
    ivy"io.getkyo::kyo-test:${V.kyo}",
    ivy"dev.zio::zio-test:${V.zio}",
    ivy"dev.zio::zio-test-sbt:${V.zio}"
  )
}
