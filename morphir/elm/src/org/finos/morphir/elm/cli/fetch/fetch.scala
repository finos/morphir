package org.finos.morphir.elm.cli.fetch
import org.finos.morphir.lang.elm.command
import org.finos.morphir.lang.elm.command.*
import org.finos.morphir.cli.{given, *}
import org.finos.morphir.elm.cli.{given, *}
import caseapp.*
import kyo.*

object Fetch extends MorphirElmCliCommand[FetchOptions]:
  def runEffect(options: FetchOptions, remainingArgs: RemainingArgs) =
    defer {
      // TODO: Perform fetch similar to https://github.com/robx/shelm/blob/master/shelm
      scribe.info("Running fetch")
      scribe.info("Fetch Options")
      scribe.info(pprint(options).render)
      val params = options.toParams
      await(command.Fetch().run(params))
    }
