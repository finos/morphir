package org.finos.morphir.elm.cli.bump
import caseapp.*
import kyo.*
import org.finos.morphir.elm.cli.*

object Bump extends MorphirElmCliCommand[BumpOptions]:
  def runEffect(options: BumpOptions, remainingArgs: RemainingArgs) =
    defer {
      pprint.log("BumpOptions:")
      pprint.log(options)
      pprint.log("Remaining Args:")
      pprint.log(remainingArgs)
      pprint.log(s"Shell: ${Main.shell}")
    }
