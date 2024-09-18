package org.finos.morphir.cli.commands

import caseapp.*
import kyo.*
import org.finos.morphir.cli.{given, *}

@HelpMessage("Work with Morphir related configuration")
final case class ConfigOptions()

object Config extends MorphirCliCommand[ConfigOptions]:
  override def group = "Setup & Configuration"
  def runEffect(options: ConfigOptions, remainingArgs: RemainingArgs) =
    defer {
      pprint.log("ConfigOptions:")
      pprint.log(options)
      pprint.log("Remaining Args:")
      pprint.log(remainingArgs)
    }
