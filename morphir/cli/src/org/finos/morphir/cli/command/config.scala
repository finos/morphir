package org.finos.morphir.cli.command

import caseapp.*
import org.finos.morphir.cli.given

final case class ConfigOptions()
object Config extends Command[ConfigOptions]:
  override def group = "Setup & Configuration"
  def run(options: ConfigOptions, remainingArgs: RemainingArgs): Unit =
    pprint.log("ConfigOptions:")
    pprint.log(options)
    pprint.log("Remaining Args:")
    pprint.log(remainingArgs)