package org.finos.morphir.lang.elm

import kyo.*
import kyo.Result
import metaconfig.{pprint as _, *}
import metaconfig.generic.*
import neotype.*
import org.finos.morphir.*
import org.finos.morphir.config.{given, *}
import org.finos.morphir.api.MajorVersionNumber
import org.finos.morphir.api.MinorVersionNumber
import org.finos.morphir.api.PatchVersionNumber
import metaconfig.Configured.Ok
import metaconfig.Configured.NotOk
import neotype.*
import neotype.interop.jsoniter.{given, *}
import com.github.plokhotnyuk.jsoniter_scala.macros.*
import com.github.plokhotnyuk.jsoniter_scala.core.*
import com.github.plokhotnyuk.jsoniter_scala.macros.JsonCodecMaker.*
import io.bullet.borer.Json

/// An Elm package version represents a version of an Elm package.
/// Elm package versions are composed of three parts: major, minor, and patch.
final case class ElmPackageVersion(major: MajorVersionNumber, minor: MinorVersionNumber, patch: PatchVersionNumber):
  override def toString(): String = s"$major.$minor.$patch"

object ElmPackageVersion:
  val pattern = "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)$".r
  inline def default: ElmPackageVersion =
    ElmPackageVersion(MajorVersionNumber.zero, MinorVersionNumber.zero, PatchVersionNumber.one)
  private val defaultJsonValueCodec = JsonCodecMaker.make[ElmPackageVersion]

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

  given jsonValueCodec: JsonValueCodec[ElmPackageVersion] = new JsonValueCodec[ElmPackageVersion] {

    def decodeValue(in: JsonReader, default: ElmPackageVersion): ElmPackageVersion =
      val b = in.nextToken()
      if b == '"' then
        in.rollbackToken()
        val str = in.readString(null)
        ElmPackageVersion.parse(str) match
          case Result.Success(value) => value
          case Result.Fail(err)      => in.decodeError(err)
          case Result.Panic(err)     => in.decodeError(err.getMessage())
      else if b == '{' then
        in.rollbackToken()
        defaultJsonValueCodec.decodeValue(in, default)
      else
        in.decodeError(
          "Expected a version string in the format of 'major.minor.patch', or an object with 'major', 'minor', and 'patch' fields."
        )

    def encodeValue(x: ElmPackageVersion, out: JsonWriter): Unit =
      out.writeVal(x.toString())
    def nullValue: ElmPackageVersion = default
  }

  inline def fromString(version: String): Result[String, ElmPackageVersion] = parse(version)

  /** Parse a ElmPackageVersion from a string.
    *
    * @param input
    *   The string to parse, should be in the format of 'major.minor.patch'
    * @return
    *   A ElmPackageVersion if the input is valid, otherwise a failure.
    */
  def parse(input: String): Result[String, ElmPackageVersion] =
    input match
      case pattern(major, minor, patch) => Result.success(ElmPackageVersion(
          MajorVersionNumber.unsafeMake(major.toInt),
          MinorVersionNumber.unsafeMake(minor.toInt),
          PatchVersionNumber.unsafeMake(patch.toInt)
        ))
      case _ => Result.fail(s"Invalid ElmPackageVersion: $input")

  /** Parse a ElmPackageVersion from a string. If the input is invalid, an IllegalArgumentException is thrown.
    * @param input
    *   The string to parse, should be in the format of 'major.minor.patch'
    * @return
    *   A ElmPackageVersion
    * @throws IllegalArgumentException
    *   if the input is invalid
    */
  def parseUnsafe(version: String): ElmPackageVersion = ElmPackageVersion.parse(version) match
    case Result.Success(value) => value
    case Result.Fail(err)      => throw new IllegalArgumentException(err)
    case Result.Panic(err)     => throw new IllegalArgumentException(err.getMessage())

  enum Interval:
    case Closed(version: ElmPackageVersion)
    case Open(version: ElmPackageVersion)
    case unbounded

  
  final case class Range(lower:Interval, upper:Interval)
end ElmPackageVersion
