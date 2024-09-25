package org.finos.morphir.lang.elm

import kyo.Result
import org.finos.morphir.api.SemVerString
import metaconfig.*
import metaconfig.generic.*
import metaconfig.sconfig.*
import org.finos.morphir.NonNegativeInt
import org.finos.morphir.config.{ConfigCompanion, MorphirConfig}
import io.bullet.borer.Reader.Config
import metaconfig.annotation.*

sealed trait ElmProject extends Product with Serializable:
  self =>
  import ElmProject.*
  def kind: ElmProject.Kind = self match
    case _: ElmPackage     => ElmProject.Kind.Package
    case _: ElmApplication => ElmProject.Kind.Application

  def sourceDirectories = self match
    case _: ElmPackage                              => List("src")
    case ElmApplication(sourceDirectories, _, _, _) => sourceDirectories

  def $type: String = self match
    case _: ElmPackage     => "package"
    case _: ElmApplication => "application"

end ElmProject

object ElmProject extends ConfigCompanion[ElmProject]:
  given confDecoder: ConfDecoder[ElmProject] = new ConfDecoder[ElmProject] {
    def read(conf: Conf): Configured[ElmProject] = conf match
      case obj @ Conf.Obj(_) =>
        obj.field("type") match
          case Some(Conf.Str("package"))     => ElmPackage.confDecoder.read(conf)
          case Some(Conf.Str("application")) => ElmApplication.confDecoder.read(conf)
          case _ => Configured.error("Expected 'type' field with value 'package' or 'application'")
      case _ => Configured.error("Expected an object")
  }

  given confEncoder: ConfEncoder[ElmProject] = new ConfEncoder[ElmProject] {
    def write(project: ElmProject): Conf = project match
      case app: ElmApplication =>
        ElmApplication.confEncoder.write(app)
      case pack: ElmPackage => ElmPackage.confEncoder.write(pack)
  }

  final case class ElmApplication(
    @ExtraName("source-directories") override val sourceDirectories: List[String],
    @ExtraName("elm-version") elmVersion: SemVerString,
    dependencies: ElmApplicationDependencies,
    @ExtraName("test-dependencies") testDependencies: ElmApplicationDependencies
  ) extends ElmProject

  object ElmApplication:
    private val default: ElmApplication = ElmApplication(
      List("src"),
      SemVerString("0.0.1"),
      ElmApplicationDependencies.default,
      ElmApplicationDependencies.default
    )
    given Surface[ElmApplication] = generic.deriveSurface
    given confDecoder: ConfDecoder[ElmApplication] =
      generic.deriveDecoder[ElmApplication](ElmApplication.default)
    given confEncoder: ConfEncoder[ElmApplication] = generic.deriveEncoder
  end ElmApplication

  final case class ElmPackage(
    @ExtraName("name") name: ElmPackageName,
    summary: Option[String],
    version: ElmPackageVersion,
    @ExtraName("elm-version") elmVersion: String,
    @ExtraName("exposed-modules") exposedModules: List[ElmModuleName],
    dependencies: Map[String, String],
    @ExtraName("test-dependencies") testDependencies: Map[String, String]
  ) extends ElmProject

  object ElmPackage:
    private val default: ElmPackage = ElmPackage(
      ElmPackageName("author/name"),
      None,
      ElmPackageVersion.default,
      "",
      List.empty,
      Map.empty,
      Map.empty
    )
    given Surface[ElmPackage] = generic.deriveSurface
    given confDecoder: ConfDecoder[ElmPackage] =
      generic.deriveDecoder[ElmPackage](ElmPackage.default).noTypos
    given confEncoder: ConfEncoder[ElmPackage] = generic.deriveEncoder
  end ElmPackage

  enum Kind:
    case Package, Application
end ElmProject

type ElmPackage = ElmProject.ElmPackage
object ElmPackage:
  export ElmProject.ElmPackage.*

type ElmApplication = ElmProject.ElmApplication
object ElmApplication:
  export ElmProject.ElmApplication.*
