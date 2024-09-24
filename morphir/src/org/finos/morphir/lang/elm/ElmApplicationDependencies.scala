package org.finos.morphir.lang.elm

import kyo.Result
import org.finos.morphir.api.SemVerString
import metaconfig.*
import metaconfig.generic.*
import metaconfig.sconfig.*
import org.finos.morphir.NonNegativeInt
import org.finos.morphir.config.{ConfigCompanion, MorphirConfig}

final case class ElmApplicationDependencies(
  direct: ElmDependencyMap,
  indirect: ElmDependencyMap
)

object ElmApplicationDependencies:
  val empty: ElmApplicationDependencies   = ElmApplicationDependencies(ElmDependencyMap.empty, ElmDependencyMap.empty)
  val default: ElmApplicationDependencies = ElmApplicationDependencies.empty

  given Surface[ElmApplicationDependencies] = generic.deriveSurface
  given confDecoder: ConfDecoder[ElmApplicationDependencies] =
    generic.deriveDecoder[ElmApplicationDependencies](ElmApplicationDependencies.default).noTypos

  given confEncoder: ConfEncoder[ElmApplicationDependencies] = generic.deriveEncoder
