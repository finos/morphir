package org.finos.morphir.elm.cli.repl
import caseapp.*

@HelpMessage("The `repl` command opens up an interactive programming session.")
final case class ReplOptions(
  interpreter: Option[String] = None,
  noColors: Boolean = false
)
