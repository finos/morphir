package org.finos.morphir.hosting
import neotype.*
import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.all.*
import org.finos.morphir.hosting.EnvironmentName.ValidCustomEnvironmentName
type ApplicationName = ApplicationName.Type
object ApplicationName extends Subtype[String]

enum EnvironmentName:
  import EnvironmentName.*
  case Development
  case Test
  case Production
  case Custom(
    name: String :| ValidCustomEnvironmentName,
    override val environmentType: EnvironmentType = EnvironmentType.Development
  )

  def environmentType: EnvironmentType = this match
    case Development                => EnvironmentType.Development
    case Test                       => EnvironmentType.Testing
    case Production                 => EnvironmentType.Production
    case Custom(_, environmentType) => environmentType

  /// Changes the environment type of a custom environment name. If the environment name is not custom, it will retain the original environment type.
  def withEnvironmentType(environmentType: EnvironmentType): EnvironmentName = this match
    case Custom(name, _) => Custom(name, environmentType)
    case other           => other

object EnvironmentName:
  type KnownEnvironmentName = Match["(?i)development|dev|test|production|prod"]
  type ValidCustomEnvironmentName = DescribedAs[
    Not[KnownEnvironmentName],
    "Custom environment name cannot be one of the reserved names: 'development', 'dev', 'test', 'production', 'prod'"
  ]
  def apply(name: String): EnvironmentName = name.toLowerCase() match
    case "development" | "dev" => Development
    case "test"                => Test
    case "production" | "prod" => Production
    case _                     => Custom(name.assume)

  def custom(
    name: String,
    environmentType: EnvironmentType = EnvironmentType.Development
  ): Either[String, EnvironmentName] =
    for
      n <- name.refineEither[ValidCustomEnvironmentName]
    yield Custom(n, environmentType)

  def customUnsafe(name: String, environmentType: EnvironmentType): EnvironmentName =
    if (name.matches("(?i)development|dev|test|production|prod")) throw new IllegalArgumentException(
      s"Custom environment name cannot be one of the reserved names: 'development', 'dev', 'test', 'production', 'prod'"
    )
    else
      Custom(name.assume, environmentType)

enum EnvironmentType:
  case Development, Testing, Staging, Production
