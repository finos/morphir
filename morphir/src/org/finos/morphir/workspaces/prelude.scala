package org.finos.morphir.workspaces
import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.string.*
import org.finos.morphir.constraint.string.* 
import metaconfig.*
import metaconfig.generic.*

/**
  * A project name.
  * Project names can contain only letters, numbers, underscores, hyphens, ands periods.
  */
opaque type ProjectName <: String :| ValidProjectName  = String :| ValidProjectName

/**
  * A project name.
  * Project names can contain only letters, numbers, underscores, hyphens, ands periods.
  */
object ProjectName extends RefinedTypeOps[String, ValidProjectName, ProjectName]:
    given Surface[ProjectName] = generic.deriveSurface[ProjectName]
    given ConfDecoder[ProjectName] = ConfDecoder[String].flatMap: input =>
        input.refineEither[ValidProjectName] match
            case Right(value) => Configured.ok(value)
            case Left(error) => Configured.error(error)

    /**
      * Tries to create a `ProjectName` by parsing a string.
      *
      * @param input The string to parse.
      * @return Either an error message or a `ProjectName`.
      */
    def parse(input:String):Either[String, ProjectName] = input.refineEither[ValidProjectName]

    /// Known project names.
    object Known:
        object Morphir:
            object SDK:
                val projectName:ProjectName = ProjectName("Morphir.SDK")