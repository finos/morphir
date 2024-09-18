package org.finos.morphir.hosting
import kyo.*
import metaconfig.*

trait Host:
  def applicationName: ApplicationName
  def loadConfig: Conf < (Env[ApplicationName] & Async & Abort[ConfError])
  def run: ExitCode < Host.Effects

object Host:
  final case class Live(applicationName: ApplicationName) extends Host:
    def loadConfig: Conf < (Env[ApplicationName] & Async & Abort[ConfError]) = ???
    def run: ExitCode < Effects                                              = ???

  type Effects = KyoApp.Effects & Env[Conf]

final case class ExitCode(code: Int)
object ExitCode:
  val success: ExitCode = ExitCode(0)
  val failure: ExitCode = ExitCode(1)

