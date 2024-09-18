package org.finos.morphir.cli.commands.shared
import caseapp.*
import caseapp.core.argparser.{ArgParser, SimpleArgParser}
import org.finos.morphir.hosting.*

@Group("Hosting Environment")
final case class HostEnvironmentOptions(
  @Group("Hosting Environment")
  environment: EnvironmentName = EnvironmentName.Development
)

object HostEnvironmentOptions
