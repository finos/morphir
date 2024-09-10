package org.finos.morphir.hosting
import dev.dirs.ProjectDirectories
import kyo.*

trait HostingConfigServiceCompanionPlatformSpecific:
  final case class Live() extends HostingConfigService:
    def applicationConfigDir: kyo.Path < IO =
      val projDirs = ProjectDirectories.from("Org", "FINOS", "Morphir")
      kyo.Path(projDirs.configDir)
