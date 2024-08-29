package org.finos.morphir.elm.cli.command

import caseapp.*

final case class MakeOptions(
    
)

object Make extends Command[MakeOptions]:
  def run(options: MakeOptions, remainingArgs: RemainingArgs): Unit =
    pprint.log("MakeOptions:")
    pprint.log(options)