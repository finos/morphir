package org.finos.morphir.cli.commands

import caseapp.*
import kyo.*
import org.finos.morphir.build.BuildInfo
import org.finos.morphir.cli.{given, *}

@HelpMessage("Display information about the Morphir CLI")
final case class AboutOptions()

object About extends MorphirCliCommand[AboutOptions]:
  override def group = "Information"
  def runEffect(options: AboutOptions, remainingArgs: RemainingArgs) =
    defer {
      println("_____________________________________________________________")
      println("Morphir CLI - A command line interface for Morphir.")
      println("_____________________________________________________________")

      val table = t2.TableBuilder()
        .add("#", "Property", "Value")
        .add("1", "Version", BuildInfo.version)
        .add("2", "Scala Version", BuildInfo.scalaVersion)
        .add("3", "Build Time", BuildInfo.buildTime)
        .add("4", "Java Version", await(System.property[String]("java.version", "N/A")))
        .add("5", "Java Home", await(System.property[String]("java.home", "N/A")))
        .add("6", "OS", s"${await(System.property[String]("os.name"))} ${await(System.property[String]("os.version"))}")
        .add("7", "User", await(System.property[String]("user.name", "N/A")))
        // TODO: Add info about Morphir Home and Setup state
        .build()

      // Create table writer with supplied configuration
      val writer = t2.TableWriter(
        "ansiColorEnabled" -> "true",
        "tableBorderColor" -> "cyan",
        "tableHeaderColor" -> "black,yellowBackground",
        "bodyRuleColor"    -> "yellow",
        "rowHeaderEnabled" -> "true",
        "rowHeaderColor"   -> "bold,cyan",
        "maxValueSize"     -> "60",
        "truncateEnabled"  -> "false"
      )

      writer.write(java.lang.System.out, table)
    }
