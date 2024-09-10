package org.finos.morphir.hosting
import dev.dirs.ProjectDirectories
import kyo.*

trait HostingConfigServiceCompanionPlatformSpecific:
  final case class Live() extends HostingConfigService:
    def applicationConfigDir: Path < IO =
      val projDirs = ProjectDirectories.from("Org", "FINOS", "Morphir")
      Path(projDirs.configDir)
