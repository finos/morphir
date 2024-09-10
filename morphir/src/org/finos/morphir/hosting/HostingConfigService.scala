package org.finos.morphir.hosting
import kyo.*

trait HostingConfigService:
  def applicationConfigDir: kyo.Path < IO

object HostingConfigService extends HostingConfigServiceCompanionPlatformSpecific
