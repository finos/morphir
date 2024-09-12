package org.finos.morphir

import neotype.*
import metaconfig.*
import metaconfig.generic.*
import metaconfig.sconfig.*
import org.finos.morphir.config.*

type NonNegativeInt = NonNegativeInt.Type

object NonNegativeInt extends Subtype[Int]:
  inline def zero: NonNegativeInt = NonNegativeInt(0)
  inline def one: NonNegativeInt  = NonNegativeInt(1)

  inline override def validate(input: Int): Boolean | String =
    input >= 0

  given confDecoder: ConfDecoder[NonNegativeInt] =
    ConfDecoder.intConfDecoder.flatMap(n => NonNegativeInt.make(n).toConfigured())
  given confEncoder: ConfEncoder[NonNegativeInt] = ConfEncoder.IntEncoder.contramap(identity)

  extension (self: NonNegativeInt)
    def value: Int = self
