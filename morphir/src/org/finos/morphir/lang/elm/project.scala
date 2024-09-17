package org.finos.morphir.lang.elm

import kyo.Result
import metaconfig.*
import metaconfig.generic.*
import metaconfig.sconfig.*
import org.finos.morphir.api.SemVerString
import org.finos.morphir.config.{ConfigCompanion, MorphirConfig}

//TODO: Add Encoders and Decoders for this using scalameta/metaconfig
//: See: https://scalameta.org/metaconfig/docs/reference.html#genericderivedecoder
//
enum ElmProject:
  self =>
  case ElmApplication(
    override val sourceDirectories: List[String],
    elmVersion: SemVerString,
    dependencies: ElmApplicationDependencies,
    testDependencies: ElmApplicationDependencies
  )
  case ElmPackage(
    name: ElmPackageName,
    summary: Option[String],
    version: ElmPackageVersion,
    elmVersion: String,
    exposedModules: List[ElmModuleName],
    dependencies: Map[String, String],
    testDependencies: Map[String, String]
  )

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

object ElmProject:
  enum Kind:
    case Package, Application

// type ElmApplication = ElmProject.ElmApplication
// object ElmApplication:
//   final case class PackageDependency(packageName:ElmPackageName, version:ElmPackageVersion)

final case class ElmApplicationDependencies(
  direct: Map[ElmPackageName, ElmPackageVersion],
  indirect: Map[ElmPackageName, ElmPackageVersion]
)

object ElmApplicationDependencies:
  import org.finos.morphir.config.transformKeys
  import org.finos.morphir.config.ToConfigured.given
  import ElmPackageName.given
  import ElmPackageVersion.given

  val default: ElmApplicationDependencies = ElmApplicationDependencies(Map.empty, Map.empty)

  given ConfEncoder[Map[ElmPackageName, ElmPackageVersion]] = {
    val base: ConfEncoder[Map[String, ElmPackageVersion]] = implicitly
    base.contramap[Map[ElmPackageName, ElmPackageVersion]]((x: Map[ElmPackageName, ElmPackageVersion]) =>
      x.map { case (k, v) => k.toString -> v }
    )
  }

  given confEncoder: ConfEncoder[ElmApplicationDependencies] =
    generic.deriveEncoder[ElmApplicationDependencies]

  given ConfDecoder[Map[ElmPackageName, ElmPackageVersion]] =
    val base: ConfDecoder[Map[String, ElmPackageVersion]] = implicitly
    ConfDecoder.from(conf =>
      base.read(conf)
    ).transformKeys((key: String) => ElmPackageName.parse(key).toConfigured())

  given Surface[ElmApplicationDependencies] = generic.deriveSurface
  given confDecoder: ConfDecoder[ElmApplicationDependencies] =
    generic.deriveDecoder[ElmApplicationDependencies](ElmApplicationDependencies.default)

type ElmPackage = ElmProject.ElmPackage
object ElmPackage
