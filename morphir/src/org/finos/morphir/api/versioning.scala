package org.finos.morphir.api

import just.semver.*
import metaconfig.*
import metaconfig.generic.*
import metaconfig.sconfig.*
import neotype.*
import org.finos.morphir.config.*

type SemVerString = SemVerString.Type
object SemVerString extends Subtype[String]:
  given confDecoder: ConfDecoder[SemVerString] =
    ConfDecoder.stringConfDecoder.flatMap(SemVerString.make(_).toConfigured())
  given confEncoder: ConfEncoder[SemVerString] = ConfEncoder.StringEncoder.contramap(identity)

  inline def semVerPattern =
    "^v?(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(?:-((?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\\.(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\\+([0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*))?$".r
  inline override def validate(input: String) = semVerPattern.matches(input)
  extension (semVer: SemVerString)
    def asSemVer: SemVer = SemVer.unsafeParse(semVer)

  def unapply(input: String): Option[SemVer] = SemVer.parse(input).toOption
