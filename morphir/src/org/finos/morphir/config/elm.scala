package org.finos.morphir.config
import metaconfig.annotation.*
import metaconfig.*
import metaconfig.generic.*
import metaconfig.Configured.Ok
import metaconfig.Configured.NotOk

final case class ElmConfigSection(
  @DeprecatedName("package", "Use package instead", "0.1.0")
  $package: Option[ElmPackageConfig] = None,
  application: Option[ElmApplicationConfig] = None
)
object ElmConfigSection:
  given Surface[ElmConfigSection]                  = generic.deriveSurface[ElmConfigSection]
  given confDecoder: ConfDecoder[ElmConfigSection] = generic.deriveDecoder[ElmConfigSection](ElmConfigSection())

final case class ElmApplicationConfig()
object ElmApplicationConfig:
  given Surface[ElmApplicationConfig] = generic.deriveSurface[ElmApplicationConfig]
  given confDecoder: ConfDecoder[ElmApplicationConfig] =
    generic.deriveDecoder[ElmApplicationConfig](ElmApplicationConfig())

final case class ElmPackageConfig()
object ElmPackageConfig:
  given Surface[ElmPackageConfig]                  = generic.deriveSurface[ElmPackageConfig]
  given confDecoder: ConfDecoder[ElmPackageConfig] = generic.deriveDecoder[ElmPackageConfig](ElmPackageConfig())
