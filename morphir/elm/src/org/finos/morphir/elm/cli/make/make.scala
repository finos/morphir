package org.finos.morphir.elm.cli.make
import caseapp.*
import org.finos.morphir.cli.given
import neotype.eval.Eval.Value

final case class MakeOptions(
  @HelpMessage("Turn on the time-travelling debugger.")
  @ValueDescription("true | false. default: false")
  debug: Boolean = false,
  optimize: Boolean = false,
  output: Option[os.Path] = None,
  report: Option[os.Path] = None,
  docs: Option[os.Path] = None
)

object Make extends Command[MakeOptions]:
  def run(options: MakeOptions, remainingArgs: RemainingArgs): Unit =
    // TODO: Implement make in such a way that if an appropriate flag or envionment variable is set
    // then it will also do a fetch. This is the path when dealing directly with elm.json.
    // We will have a morphir.conf (or something similar) that will have our definition of dependencies
    // that actually allows us to have custom packages and include the morphir.json stuff.
    pprint.log("MakeOptions:")
    pprint.log(options)
