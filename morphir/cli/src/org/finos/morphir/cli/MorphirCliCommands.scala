package org.finos.morphir.cli
import caseapp.CommandsEntryPoint
import caseapp.core.app.Command
import caseapp.core.help.*
import commands.{About, Config, Develop, Make, Setup}

class MorphirCliCommands(
  val progName: String,
  val baseRunnerName: String,
  val fullRunnerName: String
) extends CommandsEntryPoint {

  private def allCommands: Seq[MorphirCliCommand[?]] = Seq(
    About,
    Make,
    Develop,
    Setup,
    Config
  )

  def commands: Seq[Command[?]] = allCommands

  override def helpFormat: HelpFormat =
    super.helpFormat.copy(
      sortedGroups = Some(MorphirCliCommand.sortedGroups),
      sortedCommandGroups = Some(Seq("Main", "Setup & Configuration"))
    )

}
