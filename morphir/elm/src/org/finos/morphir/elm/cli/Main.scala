package org.finos.morphir.elm.cli
import caseapp.*
import make.Make
import fetch.Fetch

object Main extends CommandsEntryPoint:

  override def commands: Seq[Command[?]] = Seq(
    Fetch,
    Make
  )

  // TODO: Use the BuildInfo plugin to get the progName
  override def progName: String = "morphir-elm"
