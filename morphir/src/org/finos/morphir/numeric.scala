package org.finos.morphir

import neotype.*
import metaconfig.*
import metaconfig.generic.*
import metaconfig.sconfig.*

type PositiveInt = PositiveInt.Type

object PositiveInt extends Subtype[Int]:
  inline def zero: PositiveInt = PositiveInt(0)
  inline def one: PositiveInt  = PositiveInt(1)

  inline override def validate(input: Int): Boolean | String =
    input >= 0

  given ConfDecoder[PositiveInt] =
    ConfDecoder.intConfDecoder.flatMap(n =>
      PositiveInt.make(n) match
        case Left(value)  => Configured.error(value)
        case Right(value) => Configured.ok(value)
    )
