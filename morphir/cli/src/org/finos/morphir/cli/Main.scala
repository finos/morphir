package org.finos.morphir.cli
import org.finos.morphir.cli.command.*
import caseapp._

object Main extends CommandsEntryPoint:

  override def commands: Seq[Command[?]] = Seq(
    Make
  )

  // TODO: Use the BuildInfo plugin to get the progName
  override def progName: String = "morphir"
