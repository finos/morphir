package org.finos.morphir.cli.commands

import caseapp.*
import kyo.*
import org.finos.morphir.cli.{given, *}

@HelpMessage("Setup the Morphir CLI")
final case class SetupOptions()

object Setup extends MorphirCliCommand[SetupOptions]:
  override def group = "Setup & Configuration"
  def runEffect(options: SetupOptions, remainingArgs: RemainingArgs) =
    defer {
      pprint.log("SetupOptions:")
      pprint.log(options)
      pprint.log("Remaining Args:")
      pprint.log(remainingArgs)
    }
