package org.finos.morphir.hosting
import kyo.*
import org.finos.morphir.GenericPath

trait HostInfoService:
  self =>
  def applicationCacheDir: GenericPath < IO
  def applicationConfigDir: GenericPath < IO
  def applicationDataDir: GenericPath < IO
  def applicationPreferenceDir: GenericPath < IO

  def isWindows: Boolean < IO = osName.map(_.isWindows)
  def isLinux: Boolean < IO   = osName.map(_.isLinux)
  def isMacOS: Boolean < IO   = osName.map(_.isMacOS)
  def isOtherOS: Boolean < IO = osName.map(_.isOther)

  def userHomeDir: GenericPath < IO

  final def whenWindows[A](action: => A): Unit < IO =
    defer {
      if (await(isWindows)) action else ()
    }

  final def whenLinux[A](action: => A): Unit < IO =
    defer {
      if (await(isLinux)) action else ()
    }

  final def whenMacOS[A](action: => A): Unit < IO =
    defer {
      if (await(isMacOS)) action else ()
    }

  def whenOtherOS[A](action: String => A): Unit < IO =
    defer {
      if (await(isOtherOS)) action(await(osName).name) else ()
    }

  def osName: OsName < IO

  trait UnsafeAPI:
    def applicationCacheDir: GenericPath
    def applicationConfigDir: GenericPath
    def applicationDataDir: GenericPath
    def applicationPreferenceDir: GenericPath
    def isWindows: Boolean
    def isLinux: Boolean
    def isMacOS: Boolean
    def isOtherOs: Boolean
    def osName: OsName
    def userHomeDir: GenericPath

  def unsafe: UnsafeAPI = new UnsafeAPI:
    def applicationCacheDir: GenericPath      = KyoApp.run(self.applicationCacheDir)
    def applicationDataDir: GenericPath       = KyoApp.run(self.applicationDataDir)
    def applicationConfigDir: GenericPath     = KyoApp.run(self.applicationConfigDir)
    def applicationPreferenceDir: GenericPath = KyoApp.run(self.applicationPreferenceDir)
    def isWindows: Boolean                    = KyoApp.run(self.isWindows)
    def isLinux: Boolean                      = KyoApp.run(self.isLinux)
    def isMacOS: Boolean                      = KyoApp.run(self.isMacOS)
    def isOtherOs: Boolean                    = KyoApp.run(self.isOtherOS)
    def osName: OsName                        = KyoApp.run(self.osName)
    def userHomeDir: GenericPath              = KyoApp.run(self.userHomeDir)

object HostInfoService extends HostInfoServiceCompanionPlatformSpecific
