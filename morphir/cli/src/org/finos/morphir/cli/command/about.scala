package org.finos.morphir.cli.command

import caseapp.*
import kyo.*
import org.finos.morphir.build.BuildInfo
import org.finos.morphir.cli.{given, *}

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
        .add("4", "Java Version", System.getProperty("java.version"))
        .add("5", "Java Home", System.getProperty("java.home"))
        .add("6", "OS", s"${System.getProperty("os.name")} ${System.getProperty("os.version")}")
        .add("7", "User", System.getProperty("user.name"))
        //TODO: Add info about Morphir Home and Setup state
        .build()

      // Create table writer with supplied configuration
      val writer = t2.TableWriter(
        "ansiColorEnabled" -> "true",
        "tableBorderColor" -> "cyan",
        "tableHeaderColor" -> "black,yellowBackground",
        "bodyRuleColor"    -> "yellow",
        "rowHeaderEnabled" -> "true",
        "rowHeaderColor"   -> "bold,cyan",
        "maxValueSize" -> "60",
        "truncateEnabled" -> "false"
      )
      
      writer.write(System.out, table)
    }
