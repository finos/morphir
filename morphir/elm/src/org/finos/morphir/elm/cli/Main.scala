package org.finos.morphir.elm.cli
import org.finos.morphir.elm.cli.command.* 
import caseapp.*

object Main extends CommandsEntryPoint:

  override def commands: Seq[Command[?]] = Seq(
    Fetch,
    Make
  )

  override def progName: String = "morphir"