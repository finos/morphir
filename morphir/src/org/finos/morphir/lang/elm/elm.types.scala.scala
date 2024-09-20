package org.finos.morphir.lang.elm

import kyo.*
import kyo.Result
import metaconfig.*
import metaconfig.generic.*
import neotype.*
import org.finos.morphir.NonNegativeInt

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
  extension (self: ElmPackageName)
    def value: String = self
