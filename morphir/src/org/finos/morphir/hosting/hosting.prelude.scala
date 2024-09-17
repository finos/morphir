package org.finos.morphir.hosting
import neotype.*
type ApplicationName = ApplicationName.Type
object ApplicationName extends Subtype[String]

enum EnvironmentName:
  import EnvironmentName.*
  case Development
  case Test
  case Production
  case Custom(name: CustomEnvironmentName, override val environmentType: EnvironmentType = EnvironmentType.Development)

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
  def apply(name: String): EnvironmentName = name.toLowerCase() match
    case "development" | "dev" => Development
    case "test"                => Test
    case "production" | "prod" => Production
    case _ =>
      val customName = CustomEnvironmentName.unsafeMake(name)
      Custom(customName)

  def custom(
    name: String,
    environmentType: EnvironmentType = EnvironmentType.Development
  ): Either[String, EnvironmentName] = CustomEnvironmentName.make(name).right.map(Custom(_, environmentType))

  def customUnsafe(name: String, environmentType: EnvironmentType): EnvironmentName =
    CustomEnvironmentName.make(name).fold(
      error => throw new IllegalArgumentException(error),
      Custom(_, environmentType)
    )

enum EnvironmentType:
  case Development, Testing, Staging, Production

type CustomEnvironmentName = CustomEnvironmentName.Type
object CustomEnvironmentName extends Subtype[String]:
  inline override def validate(input: String): Boolean | String =
    if (input.matches("(?i)development|dev|test|production|prod"))
      s"Custom environment name cannot be one of the reserved names: 'development', 'dev', 'test', 'production', 'prod'"
    else true
