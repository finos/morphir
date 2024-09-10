package org.finos.morphir.hosting
import kyo.*

trait HostingConfigService:
  def applicationConfigDir: Path < IO

object HostingConfigService extends HostingConfigServiceCompanionPlatformSpecific
