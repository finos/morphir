package org.finos.morphir.hosting
import kyo.*
import metaconfig.*
import org.finos.morphir.config.*

trait HostedService:
  def start(conf: Conf): Unit < (Env[MorphirConfig] & Async & Abort[Throwable])
  def stop(conf: Conf): Unit < (Env[MorphirConfig] & Async & Abort[Throwable])
