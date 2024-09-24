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

type ElmPackageName = ElmPackageName.Type
object ElmPackageName extends Subtype[String]:
  inline def pattern = "^(?<author>[-a-zA-Z0-9@:%_\\+.~#?&]{2,})/(?<name>[-a-zA-Z0-9@:%_\\+.~#?&]{2,})$".r
  inline override def validate(input: String) = pattern.matches(input)

  given confEncoder: ConfEncoder[ElmPackageName] = ConfEncoder.StringEncoder.contramap(_.value)

  given confDecoder: ConfDecoder[ElmPackageName] = ConfDecoder.stringConfDecoder.flatMap: str =>
    parse(str).fold((err: Result.Error[String]) => Configured.error(err.show))(Configured.ok)

  given jsonKeyCodec: JsonKeyCodec[ElmPackageName] = new JsonKeyCodec[ElmPackageName] {
    def encodeKey(x: ElmPackageName, out: JsonWriter): Unit = out.writeKey(x.value)
    def decodeKey(in: JsonReader): ElmPackageName =
      val b = in.nextToken()
      if b == '"' then
        in.rollbackToken()
        val str = in.readKeyAsString()
        ElmPackageName.parse(str) match
          case Result.Success(value) => value
          case Result.Fail(err)      => in.decodeError(err)
          case Result.Panic(err)     => in.decodeError(err.getMessage())
      else
        in.decodeError("Expected a string")
  }

  given jsonValueCodec: JsonValueCodec[ElmPackageName] = subtypeCodec[String, ElmPackageName]

  def parse(input: String): Result[String, ElmPackageName] = Result.fromEither(make(input))
  def parseAsConfigured(input: String): Configured[ElmPackageName] =
    parse(input).fold((err: Result[String, ElmPackageName]) => Configured.error(err.show))(Configured.ok)

  extension (self: ElmPackageName)
    def value: String = self
