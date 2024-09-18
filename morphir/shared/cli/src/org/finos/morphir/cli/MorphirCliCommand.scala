package org.finos.morphir.cli
import caseapp.*
import kyo.*
import org.finos.morphir.config.*
import caseapp.core.help.HelpFormat

abstract class MorphirCliCommand[T](using parser: Parser[T], help: Help[T]) extends Command[T]()(parser, help):

  def run(options: T, remainingArgs: RemainingArgs): Unit =
    KyoApp.run(runEffect(options, remainingArgs))

  def runEffect(options: T, remainingArgs: RemainingArgs): Unit < (Async & Resource & Abort[Throwable])

  override def helpFormat: HelpFormat = super.helpFormat.copy(
    sortedGroups = Some(MorphirCliCommand.sortedGroups)
  )

object MorphirCliCommand:
  val sortedGroups = Seq("Main", "Primary", "Secondary", "User", "Other", "Formatting", "Hosting Environment", "Help")
  type Effects = KyoApp.Effects & Env[MorphirConfig]
