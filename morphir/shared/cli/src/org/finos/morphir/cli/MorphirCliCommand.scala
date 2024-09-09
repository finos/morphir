package org.finos.morphir.cli
import caseapp.*
import kyo.*

abstract class MorphirCliCommand[T](using parser: Parser[T], help: Help[T]) extends Command[T]()(parser, help):
  def run(options: T, remainingArgs: RemainingArgs): Unit =
    KyoApp.run(runEffect(options, remainingArgs))

  def runEffect(options: T, remainingArgs: RemainingArgs): Unit < (IO & Abort[Throwable])
