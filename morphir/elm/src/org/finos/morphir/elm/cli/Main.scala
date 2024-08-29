package org.finos.morphir.elm.cli
import org.finos.morphir.elm.cli.command.* 
import caseapp.*

object Main extends CommandsEntryPoint:

  override def commands: Seq[Command[?]] = Seq(
    Fetch,
    Make
  )

  // TODO: Use the BuildInfo plugin to get the progName
  override def progName: String = "morphir-elm"