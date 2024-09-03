package org.finos.morphir.elm.cli.fetch
import org.finos.morphir.cli.given
import caseapp.*
import kyo.Path

final case class FetchOptions(projectDir:Option[os.Path])

object Fetch extends Command[FetchOptions]:
  def run(options: FetchOptions, remainingArgs: RemainingArgs): Unit =
    pprint.log("FetchOptions:")
    pprint.log(options)

  def task(options:FetchOptions) = 
    Path()
