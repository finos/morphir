package org.finos.morphir.lang.elm

import kyo.*
import kyo.Result
import metaconfig.*
import metaconfig.generic.*
import neotype.*
import org.finos.morphir.*
import org.finos.morphir.config.{given, *}
import org.finos.morphir.api.MajorVersionNumber
import org.finos.morphir.api.MinorVersionNumber
import org.finos.morphir.api.PatchVersionNumber
import metaconfig.Configured.Ok
import metaconfig.Configured.NotOk

type ElmModuleName = ElmModuleName.Type

object ElmModuleName extends Subtype[String]:
  inline def pattern                                   = "^([A-Z][a-zA-Z0-9]*)(\\.[A-Z][a-zA-Z0-9]*)*$".r
  inline override def validate(input: String): Boolean = pattern.matches(input)

  given confEncoder: ConfEncoder[ElmModuleName] = ConfEncoder.StringEncoder.contramap(_.value)

  given confDecoder: ConfDecoder[ElmModuleName] = ConfDecoder.stringConfDecoder.flatMap {
    str =>
      parse(str).fold((err: Result.Error[String]) => Configured.error(err.show))(Configured.ok)
  }

  def parse(input: String): Result[String, ElmModuleName] = Result.fromEither(make(input))

  extension (self: ElmModuleName)
    def value: String = self
    def namespace: Option[String] =
      if (!validate(value)) None
      else
        Some(value.split("\\.").dropRight(1).mkString("."))

type ElmPackageName = ElmPackageName.Type
object ElmPackageName extends Subtype[String]:
  inline def pattern = "^(?<author>[-a-zA-Z0-9@:%_\\+.~#?&]{2,})/(?<name>[-a-zA-Z0-9@:%_\\+.~#?&]{2,})$".r
  inline override def validate(input: String) = pattern.matches(input)

  given confEncoder: ConfEncoder[ElmPackageName] = ConfEncoder.StringEncoder.contramap(_.value)

  given confDecoder: ConfDecoder[ElmPackageName] = ConfDecoder.stringConfDecoder.flatMap: str =>
    parse(str).fold((err: Result.Error[String]) => Configured.error(err.show))(Configured.ok)

  def parse(input: String): Result[String, ElmPackageName] = Result.fromEither(make(input))
  def parseAsConfigured(input: String): Configured[ElmPackageName] =
    parse(input).fold((err: Result[String, ElmPackageName]) => Configured.error(err.show))(Configured.ok)

  extension (self: ElmPackageName)
    def value: String = self

final case class ElmPackageVersion(major: MajorVersionNumber, minor: MinorVersionNumber, patch: PatchVersionNumber):
  override def toString(): String = s"$major.$minor.$patch"

object ElmPackageVersion:
  val pattern = "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)$".r
  inline def default: ElmPackageVersion =
    ElmPackageVersion(MajorVersionNumber.zero, MinorVersionNumber.zero, PatchVersionNumber.one)

  given confEncoder: ConfEncoder[ElmPackageVersion] = ConfEncoder.StringEncoder.contramap(vers => vers.toString())
  given confDecoder: ConfDecoder[ElmPackageVersion] = new ConfDecoder[ElmPackageVersion] {
    def read(conf: Conf): Configured[ElmPackageVersion] = conf match
      case Conf.Str(pattern(major, minor, patch)) =>
        Configured.ok(ElmPackageVersion(
          MajorVersionNumber.unsafeMake(major.toInt),
          MinorVersionNumber.unsafeMake(minor.toInt),
          PatchVersionNumber.unsafeMake(patch.toInt)
        ))
      case c @ Conf.Obj(_) =>
        val major = c.get[MajorVersionNumber]("major")
        val minor = c.get[MinorVersionNumber]("minor")
        val patch = c.get[PatchVersionNumber]("patch")
        (major |@| minor |@| patch) match
          case Ok(((major, minor), patch)) => Configured.ok(ElmPackageVersion(major, minor, patch))
          case NotOk(error)                => Configured.error(s"Invalid ElmPackageVersion: $error")
      case other =>
        Configured.error(s"Invalid ElmPackageVersion: $other")
  }

end ElmPackageVersion

type ElmDependencyMap = ElmDependencyMap.Type
object ElmDependencyMap extends Subtype[Map[ElmPackageName, ElmPackageVersion]]:
  given confDecoder: ConfDecoder[ElmDependencyMap] =
    ConfDecoder[Map[String, ElmPackageVersion]]
      .transformKeys[ElmPackageName](key => ElmPackageName.parseAsConfigured(key))
      .map(unsafeMake(_))
end ElmDependencyMap
