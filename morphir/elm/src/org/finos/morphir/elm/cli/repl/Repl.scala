package org.finos.morphir.elm.cli.repl
import caseapp.*
import kyo.*
import org.finos.morphir.elm.cli.*

object Repl extends MorphirElmCliCommand[ReplOptions]:
  def runEffect(options: ReplOptions, remainingArgs: RemainingArgs) =
    defer {
      pprint.log("ReplOptions:")
      pprint.log(options)
      pprint.log("Remaining Args:")
      pprint.log(remainingArgs)
      pprint.log(s"Shell: ${Main.shell}")
    }
