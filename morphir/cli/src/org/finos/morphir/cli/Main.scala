package org.finos.morphir.cli
import org.finos.morphir.cli.command.*
import caseapp.*
import caseapp.core.help.*
object Main extends CommandsEntryPoint:

  override def commands: Seq[Command[?]] = Seq(
    About,
    Make,
    Develop,
    Setup,
    Config
  )

  override def helpFormat: HelpFormat =
    super.helpFormat.copy(sortedCommandGroups = Some(Seq("Main", "Setup & Configuration")))

  // TODO: Use the BuildInfo plugin to get the progName
  override def progName: String = "morphir"
