package org.finos.morphir.config
import org.finos.morphir.workspaces.*
import metaconfig.*
import metaconfig.annotation.Inline
import metaconfig.generic.* 
import io.github.iltotore.iron.*

final case class ProjectInfo(name:ProjectName, description:Option[String] = None)

object ProjectInfo:
    lazy val default: ProjectInfo = ProjectInfo(
        name = ProjectName("Morphir"),
        description = None
    )
    given Surface[ProjectInfo] = generic.deriveSurface
    given ConfDecoder[ProjectInfo] = generic.deriveDecoder[ProjectInfo](default)

sealed abstract class Project extends Product with Serializable:
    inline def name: ProjectName
    inline def description: Option[String]

final case class Library(
    @Inline
    info:ProjectInfo
) extends Project:
    inline def name: ProjectName = info.name
    inline def description: Option[String] = info.description

final case class Application(
    @Inline
    info:ProjectInfo
) extends Project:
    inline def name: ProjectName = info.name
    inline def description: Option[String] = info.description