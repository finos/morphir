package org.finos.morphir.cli.commands

import caseapp.*
import kyo.*
import org.finos.morphir.cli.{given, *}
import caseapp.core.Arg

@HelpMessage("Work with Morphir related configuration")
final case class ConfigOptions()

object Config extends MorphirCliCommand[ConfigOptions]:
  override def group = "Setup & Configuration"
  def runEffect(options: ConfigOptions, remainingArgs: RemainingArgs) =
    defer {
      pprint.log("ConfigOptions:")
      pprint.log(options)
      pprint.log("Remaining Args:")
      pprint.log(remainingArgs)
    }

@HelpMessage("Set configuration options")
final case class ConfigSetOptions(key: String)
object ConfigSet extends MorphirCliCommand[ConfigSetOptions]:
  override def names: List[List[String]] = List(List("config", "set"))
  override def group                     = "Setup & Configuration"
  def runEffect(options: ConfigSetOptions, remainingArgs: RemainingArgs) =
    defer {
      pprint.log("ConfigSetOptions:")
      pprint.log(options)
      pprint.log("Remaining Args:")
      pprint.log(remainingArgs)
    }

  @HelpMessage("Get configuration options")
  @ArgsName("key")
  final case class ConfigGetOptions()
  object ConfigGet extends MorphirCliCommand[ConfigGetOptions]:
    override def names: List[List[String]] = List(List("config", "get"))
    override def group                     = "Setup & Configuration"
    def runEffect(options: ConfigGetOptions, remainingArgs: RemainingArgs) =
      defer {
        pprint.log("ConfigGetOptions:")
        pprint.log(options)
        pprint.log("Remaining Args:")
        pprint.log(remainingArgs)
      }
