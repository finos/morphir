package org.finos.morphir.config
import metaconfig.* 
import metaconfig.generic.* 

final case class Workspace(members: Vector[String] = Vector.empty)
object Workspace:
    given Surface[Workspace] = generic.deriveSurface
    given ConfDecoder[Workspace] = generic.deriveDecoder[Workspace](Workspace())
