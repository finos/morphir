package org.finos.morphir.cli.command

import caseapp.*
import org.finos.morphir.cli.given

final case class SetupOptions()

object Setup extends Command[SetupOptions]:
  override def group = "Setup & Configuration"
  def run(options: SetupOptions, remainingArgs: RemainingArgs): Unit =
    pprint.log("SetupOptions:")
    pprint.log(options)
    pprint.log("Remaining Args:")
    pprint.log(remainingArgs)
