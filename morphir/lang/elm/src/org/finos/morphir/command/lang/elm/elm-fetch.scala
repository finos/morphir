package org.finos.morphir.lang.elm.command

import org.finos.morphir.command.*
import scala.Console as _
import kyo.*

final case class FetchParams(projectDir: kyo.Path)

final case class Fetch() extends Command[FetchParams]:
  def run(params: FetchParams): Unit < (IO & Abort[Throwable]) =
    defer {
      await(Console.println("Running fetch"))
      await(Console.println("Fetch Params", pprint(params)))
    }
