package org.finos.morphir.elm.cli.fetch
import org.finos.morphir.lang.elm.command
import org.finos.morphir.lang.elm.command.*
import org.finos.morphir.cli.given
import caseapp.*
import kyo.*

final case class FetchOptions(projectDir: Option[kyo.Path] = None):
  def toParams: FetchParams =
    FetchParams(projectDir.getOrElse(kyo.Path(os.pwd.toString)))

object Fetch extends Command[FetchOptions]:
  def run(options: FetchOptions, remainingArgs: RemainingArgs): Unit =
    // TODO: Perform fetch similar to https://github.com/robx/shelm/blob/master/shelm
    scribe.info("Running fetch")
    scribe.info("Fetch Options")
    scribe.info(pprint(options).render)
    KyoApp.run(task(options))

  def task(options: FetchOptions) =
    val params = options.toParams
    command.Fetch().run(params)
