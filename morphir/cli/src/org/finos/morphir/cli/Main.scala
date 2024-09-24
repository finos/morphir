package org.finos.morphir.cli
import caseapp.*
import caseapp.core.help.*
import commands.{About, Config, Develop, Make, Setup}
object Main:
  def main(args: Array[String]): Unit =
    val commands = new MorphirCliCommands("morphir-cli", "morphir-cli", "Morphir CLI")
    commands.main(args)
