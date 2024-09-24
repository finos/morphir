package org.finos.morphir.elm.cli
import caseapp.*
import make.Make
import fetch.Fetch
import repl.Repl
import bump.Bump
object Main extends CommandsEntryPoint:

  override def commands: Seq[Command[?]] = Seq(
    Fetch,
    Make,
    Repl,
    Bump
  )

  // TODO: Use the BuildInfo plugin to get the progName
  override def progName: String = "morphir-elm"
