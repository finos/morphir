package org.finos.morphir.hosting

import org.finos.morphir.Path
import org.finos.morphir.GenericPath

final case class HostEnvironment(
  applicationName: ApplicationName,
  environmentName: EnvironmentName,
  contentRoot: os.BasePath
)
