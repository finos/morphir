package org.finos.morphir.config
import metaconfig.* 
import metaconfig.generic.* 

final case class Workspace(projects: IndexedSeq[String] = IndexedSeq.empty)
object Workspace:
    given Surface[Workspace] = generic.deriveSurface
    given ConfDecoder[Workspace] = generic.deriveDecoder[Workspace](Workspace())
