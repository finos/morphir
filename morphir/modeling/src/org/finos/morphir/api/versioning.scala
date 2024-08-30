package org.finos.morphir.api

import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.string.*

type SemVerString = String :| SemanticVersion
object SemVerString extends RefinedTypeOps.Transparent[SemVerString]