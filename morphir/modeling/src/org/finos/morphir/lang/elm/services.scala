package org.finos.morphir.lang.elm

import kyo.{Path as _, _}
import org.finos.morphir.fs.*
import java.net.{URI, URL}

// trait ElmProjectInfoService:
//     self =>

//     def sourceDirectories(project: ElmProject): List[String] < IO

// object ElmProjectInfoService:
//     def apply(): ElmProjectInfoService = new ElmProjectInfoService {
//         override def sourceDirectories(project: ElmProject): List[String] < IO =
//             project match
//                 case _:ElmProject.ElmPackage => ???
//                 case _: ElmProject.ElmApplication => ???
//     }

trait ElmProjectLoader:
  def loadProject(path: Path): ElmProject < IO & Abort[String | Exception]
  def loadProject(uri: URI): ElmProject < IO & Abort[String | Exception]

object ElmProjectLoader:
  final case class Live() extends ElmProjectLoader:
    override def loadProject(path: Path): ElmProject < IO & Abort[String | Exception] = ???
    override def loadProject(uri: URI): ElmProject < IO & Abort[String | Exception]   = ???

trait ElmPackageResolver:
  import ElmPackageResolver.*
  /// Resolve a package by name and version
  def resolve(packageName: ElmPackageName, version: ElmPackageVersion): ResolveResult < IO & Abort[String | Exception]
  def resolveAll(packages: Map[ElmPackageName, ElmPackageVersion])
    : Map[ElmPackageName, ResolveResult] < IO & Abort[String | Exception]

object ElmPackageResolver:
  final case class ResolveResult(
    packageName: String,
    version: String,
    source: PackageSource,
    config: Map[String, String]
  )

  // TODO: Create a resolver that is configurable and able resolve packages from different sources
  //      - The resolver should take into account the project configuration and Morphir's own manifest and configuration

enum PackageSource:
  case Local(path: Path)
  case Remote(uri: URI)
  case Git(Url: URL, ref: Option[String], path: Option[String])
  case GitHub(owner: String, repo: String, ref: Option[String], path: Option[String])
  case GitHubEnterprise(owner: String, repo: String, baseUrl: URL, ref: Option[String], path: Option[String])
