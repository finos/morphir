package org.finos.morphir.hosting
import dev.dirs.*
import org.finos.morphir.*
import kyo.{Path as _, *}
trait HostInfoServiceCompanionPlatformSpecific:
  final case class Live() extends HostInfoService:
    import Live.*

    def applicationCacheDir: GenericPath < IO =
      val projDirs = ProjectDirectories.from(qualifier, organization, qualifier)
      Path.parse(projDirs.cacheDir)

    def applicationDataDir: GenericPath < IO =
      val projDirs = ProjectDirectories.from(qualifier, organization, application)
      Path.parse(projDirs.dataDir)

    def applicationConfigDir: GenericPath < IO =
      val projDirs = ProjectDirectories.from(qualifier, organization, application)
      Path.parse(projDirs.configDir)

    def applicationPreferenceDir: GenericPath < IO =
      val projDirs = ProjectDirectories.from(qualifier, organization, application)
      Path.parse(projDirs.preferenceDir)

    def osName: OsName < IO = OsName()

    def userHomeDir: GenericPath < IO = Path.parse(UserDirectories.get().homeDir)
  object Live:
    val qualifier: String    = "Org"
    val organization: String = "FINOS"
    val application: String  = "Morphir"
