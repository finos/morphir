package org.finos.morphir.cli.options

object OptionGroup:
  val help               = "Help"
  val setup              = "Setup & Configuration"
  val hostingEnvironment = "Hosting Environment"
  val main               = "Main"
  val primary            = "Primary"
  val secondary          = "Secondary"
  val user               = "User"
  val elm                = "Elm"

  val order: Seq[String] = Seq(main, primary, elm, secondary, user, hostingEnvironment, setup, help)
end OptionGroup
