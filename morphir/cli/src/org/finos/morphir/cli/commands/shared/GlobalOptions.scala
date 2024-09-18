package org.finos.morphir.cli.commands.shared
import caseapp.*

final case class GlobalOptions(
  @Recurse
  environmentOptions: HostEnvironmentOptions = HostEnvironmentOptions()
)
 
object GlobalOptions:
  val default = GlobalOptions()
