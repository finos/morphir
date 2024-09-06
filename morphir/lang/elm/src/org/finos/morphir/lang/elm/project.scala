package org.finos.morphir.lang.elm

import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.numeric.*
import io.github.iltotore.iron.constraint.string.*
import org.finos.morphir.constraint.string.*
import org.finos.morphir.lang.elm.constraint.string.*
import org.finos.morphir.api.SemVerString

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

opaque type ElmPackageName <: String :| ValidElmPackageName = String :| ValidElmPackageName
object ElmPackageName extends RefinedTypeOps[String, ValidElmPackageName, ElmPackageName]

final case class ElmPackageVersion(major: Int :| Positive0, minor: Int :| Positive0, patch: Int :| Positive0):
  override def toString(): String = s"$major.$minor.$patch"

// type ElmApplication = ElmProject.ElmApplication
// object ElmApplication:
//   final case class PackageDependency(packageName:ElmPackageName, version:ElmPackageVersion)

final case class ElmApplicationDependencies(
  direct: Map[ElmPackageName, ElmPackageVersion],
  indirect: Map[ElmPackageName, ElmPackageVersion]
)

type ElmPackage = ElmProject.ElmPackage
object ElmPackage

opaque type ElmModuleName <: String :| ValidElmModuleName = String :| ValidElmModuleName
object ElmModuleName extends RefinedTypeOps[String, ValidElmModuleName, ElmModuleName]:
  extension (name: ElmModuleName)
    def namespace: Option[ElmModuleName] =
      val idx = name.lastIndexOf('.')
      if idx < 0 then
        None
      else
        Some(ElmModuleName.assume(name.substring(0, idx)))
