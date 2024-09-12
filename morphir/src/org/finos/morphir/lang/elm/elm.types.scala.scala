package org.finos.morphir.lang.elm

import kyo.*
import metaconfig.*
import metaconfig.generic.*
import neotype.*

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
