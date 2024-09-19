package org.finos.morphir.lang.elm

import kyo.{Path as _, *}
import metaconfig.*
import metaconfig.generic.*
import neotype.*
import just.semver.*
import org.finos.morphir.*
import org.finos.morphir.api.*

final case class ElmCachingInfo(
  homeDirectory: GenericPath,
  packageCacheDirectory: GenericPath,
  registryFilePath: GenericPath
)

object ElmCachingInfo:
  def vendored(elmVersion: SemVerString, pwd: GenericPath): ElmCachingInfo =
    vendored(elmVersion.asSemVer, pwd)

  def vendored(elmVersion: SemVer, pwd: GenericPath): ElmCachingInfo =
    val homeDirectory         = pwd / RelativePath.parse(s"home/elm-stuff/$elmVersion")
    val packageCacheDirectory = homeDirectory / "package-cache"
    val registryFilePath      = homeDirectory / "registry.json"
    ElmCachingInfo(homeDirectory, packageCacheDirectory, registryFilePath)
