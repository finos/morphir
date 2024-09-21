package org.finos.morphir.api

import com.github.plokhotnyuk.jsoniter_scala.macros.*
import com.github.plokhotnyuk.jsoniter_scala.core.*
import just.semver.*
import metaconfig.*
import metaconfig.generic.*
import metaconfig.sconfig.*
import neotype.*
import neotype.interop.jsoniter.{given, *}
import com.github.plokhotnyuk.jsoniter_scala.macros.*
import com.github.plokhotnyuk.jsoniter_scala.core.*
import com.github.plokhotnyuk.jsoniter_scala.macros.JsonCodecMaker.*
import org.finos.morphir.config.*
import org.typelevel.literally.Literally
import scala.quoted.Quotes
import org.finos.morphir.trees.graph.Literal

type SemVerString = SemVerString.Type
object SemVerString extends Subtype[String]:
  given jsonCodec: JsonValueCodec[SemVerString] = subtypeCodec[String, SemVerString]
  given confDecoder: ConfDecoder[SemVerString] =
    ConfDecoder.stringConfDecoder.flatMap(SemVerString.make(_).toConfigured())
  given confEncoder: ConfEncoder[SemVerString] = ConfEncoder.StringEncoder.contramap(identity)

  inline def semVerPattern =
    "^v?(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(?:-((?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\\.(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\\+([0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*))?$".r
  inline override def validate(input: String) = semVerPattern.matches(input)
  extension (semVer: SemVerString)
    def asSemVer: SemVer = SemVer.unsafeParse(semVer)

  def unapply(input: String): Option[SemVer] = SemVer.parse(input).toOption
end SemVerString

type MajorVersionNumber = MajorVersionNumber.Type
object MajorVersionNumber extends Subtype[Int]:
  val one                      = MajorVersionNumber(1)
  val zero: MajorVersionNumber = MajorVersionNumber(0)
  inline override def validate(input: Int): Boolean | String =
    input >= 0
  given confDecoder: ConfDecoder[MajorVersionNumber] =
    ConfDecoder.intConfDecoder.flatMap(n => MajorVersionNumber.make(n).toConfigured())
  given confEncoder: ConfEncoder[MajorVersionNumber] = ConfEncoder.IntEncoder.contramap(identity)
end MajorVersionNumber

type MinorVersionNumber = MinorVersionNumber.Type
object MinorVersionNumber extends Subtype[Int]:
  val one                      = MinorVersionNumber(1)
  val zero: MinorVersionNumber = MinorVersionNumber(0)
  inline override def validate(input: Int): Boolean | String =
    input >= 0
  given confDecoder: ConfDecoder[MinorVersionNumber] =
    ConfDecoder.intConfDecoder.flatMap(n => MinorVersionNumber.make(n).toConfigured())
  given confEncoder: ConfEncoder[MinorVersionNumber] = ConfEncoder.IntEncoder.contramap(identity)
end MinorVersionNumber

type PatchVersionNumber = PatchVersionNumber.Type
object PatchVersionNumber extends Subtype[Int]:
  val one                      = PatchVersionNumber(1)
  val zero: PatchVersionNumber = PatchVersionNumber(0)
  inline override def validate(input: Int): Boolean | String =
    input >= 0
  given confDecoder: ConfDecoder[PatchVersionNumber] =
    ConfDecoder.intConfDecoder.flatMap(n => PatchVersionNumber.make(n).toConfigured())
  given confEncoder: ConfEncoder[PatchVersionNumber] = ConfEncoder.IntEncoder.contramap(identity)
end PatchVersionNumber

extension (inline ctx: StringContext)
  inline def major(inline args: Any*): MajorVersionNumber =
    ${ MajorLiteral('ctx, 'args) }

  inline def minor(inline args: Any*): MinorVersionNumber =
    ${ MinorLiteral('ctx, 'args) }

  inline def patch(inline args: Any*): PatchVersionNumber =
    ${ PatchLiteral('ctx, 'args) }

object MajorLiteral extends Literally[MajorVersionNumber]:
  def validate(input: String)(using Quotes) =
    input.toIntOption match
      case Some(n) if n >= 0 => Right('{ MajorVersionNumber.unsafeMake(${ Expr(n) }) })
      case _ => Left(s"invalid major version number: $input, a major version number must be a non-negative integer")
end MajorLiteral

object MinorLiteral extends Literally[MinorVersionNumber]:
  def validate(input: String)(using Quotes) =
    input.toIntOption match
      case Some(n) if n >= 0 => Right('{ MinorVersionNumber.unsafeMake(${ Expr(n) }) })
      case _ => Left(s"invalid minor version number: $input, a minor version number must be a non-negative integer")
end MinorLiteral

object PatchLiteral extends Literally[PatchVersionNumber]:
  def validate(input: String)(using Quotes) =
    input.toIntOption match
      case Some(n) if n >= 0 => Right('{ PatchVersionNumber.unsafeMake(${ Expr(n) }) })
      case _ => Left(s"invalid patch version number: $input, a patch version number must be a non-negative integer")
end PatchLiteral
