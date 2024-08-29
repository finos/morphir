package org.finos.morphir.elm.cli.command
import caseapp.*
import org.finos.morphir.cli.given

final case class MakeOptions(
    debug: Boolean = false,
    optimize: Boolean = false,
    output: Option[os.Path] = None,
    report: Option[os.Path] = None,
    docs: Option[os.Path] = None,
)

object Make extends Command[MakeOptions]:
  def run(options: MakeOptions, remainingArgs: RemainingArgs): Unit =
    pprint.log("MakeOptions:")
    pprint.log(options)