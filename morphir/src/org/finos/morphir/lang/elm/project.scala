package org.finos.morphir.lang.elm

import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.numeric.*
import io.github.iltotore.iron.constraint.string.*
import kyo.Result
import org.finos.morphir.constraint.string.*
import org.finos.morphir.lang.elm.constraint.string.*
import org.finos.morphir.api.SemVerString
import metaconfig.*
import metaconfig.generic.*
import metaconfig.sconfig.*
import org.finos.morphir.NonNegativeInt
import org.finos.morphir.config.{ConfigCompanion, MorphirConfig}

inline given [T](using mirror: RefinedTypeOps.Mirror[T], ev: ConfDecoder[mirror.IronType]): ConfDecoder[T] =
  ev.asInstanceOf[ConfDecoder[T]]

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

final case class ElmPackageVersion(major: NonNegativeInt, minor: NonNegativeInt, patch: NonNegativeInt):
  override def toString(): String = s"$major.$minor.$patch"

object ElmPackageVersion:
  inline def default: ElmPackageVersion =
    ElmPackageVersion(NonNegativeInt.zero, NonNegativeInt.zero, NonNegativeInt.one)

  given Surface[ElmPackageVersion] = generic.deriveSurface
  given confDecoder: ConfDecoder[ElmPackageVersion] =
    generic.deriveDecoder[ElmPackageVersion](ElmPackageVersion.default)

// type ElmApplication = ElmProject.ElmApplication
// object ElmApplication:
//   final case class PackageDependency(packageName:ElmPackageName, version:ElmPackageVersion)

final case class ElmApplicationDependencies(
  direct: Map[String, ElmPackageVersion],
  indirect: Map[String, ElmPackageVersion]
) // TODO: change this to ElmPackageName

object ElmApplicationDependencies:
  val default: ElmApplicationDependencies = ElmApplicationDependencies(Map.empty, Map.empty)

  given Surface[ElmApplicationDependencies] = generic.deriveSurface
  given confDecoder: ConfDecoder[ElmApplicationDependencies] =
    generic.deriveDecoder[ElmApplicationDependencies](ElmApplicationDependencies.default)

type ElmPackage = ElmProject.ElmPackage
object ElmPackage
