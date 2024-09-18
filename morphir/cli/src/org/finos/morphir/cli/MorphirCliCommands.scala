package org.finos.morphir.cli
import caseapp.CommandsEntryPoint
import caseapp.core.app.Command
import caseapp.core.help.*
import commands.{About, Config, Develop, Make, Setup}
import org.finos.morphir.cli.options.*
import org.finos.morphir.cli.commands.ConfigSet
import org.finos.morphir.cli.commands.ConfigSet.ConfigGet
import org.finos.morphir.cli.MorphirCliCommand

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
    ConfigGet,
    Config,
    ConfigSet
  )

  def commands: Seq[Command[?]] = allCommands

  override def helpFormat: HelpFormat =
    super.helpFormat.copy(
      sortedGroups = Some(OptionGroup.order),
      sortedCommandGroups = Some(Seq("Main", "Setup & Configuration"))
    )

}
