package org.finos.morphir.cli
import caseapp.*
import kyo.*
import org.finos.morphir.config.*
import org.finos.morphir.cli.options.OptionGroup
import caseapp.core.help.HelpFormat

abstract class MorphirCliCommand[T](using parser: Parser[T], help: Help[T]) extends Command[T]()(parser, help):

  def run(options: T, remainingArgs: RemainingArgs): Unit =
    KyoApp.run(runEffect(options, remainingArgs))

  def runEffect(options: T, remainingArgs: RemainingArgs): Unit < (Async & Resource & Abort[Throwable])

  override def helpFormat: HelpFormat = super.helpFormat.copy(
    sortedGroups = Some(OptionGroup.order)
  )

object MorphirCliCommand:
  type Effects = KyoApp.Effects & Env[MorphirConfig]
