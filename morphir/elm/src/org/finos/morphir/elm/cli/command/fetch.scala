package org.finos.morphir.elm.cli.command
import caseapp.*
final case class FetchOptions()

object Fetch extends Command[FetchOptions]:
  def run(options: FetchOptions, remainingArgs: RemainingArgs): Unit =
    pprint.log("FetchOptions:")
    pprint.log(options)
