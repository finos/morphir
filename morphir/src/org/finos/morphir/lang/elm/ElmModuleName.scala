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

/// Represents an Elm module name.
/// Elm module names are composed of one or more dot-separated parts, each of which must start with an uppercase letter.
type ElmModuleName = ElmModuleName.Type

/// Companion object for ElmModuleName,
/// an Elm module name is a dot-separated list of one or more parts, each of which must start with an uppercase letter.
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
