package org.finos.morphir.config

import metaconfig.* 
import metaconfig.generic.* 

final case class MorphirConfig(
    workspace: Workspace
)
object MorphirConfig:
    given Surface[MorphirConfig] = generic.deriveSurface
    given ConfDecoder[MorphirConfig] = generic.deriveDecoder[MorphirConfig](MorphirConfig(Workspace()))