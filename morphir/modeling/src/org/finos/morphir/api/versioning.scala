package org.finos.morphir.api

import just.semver.* 
import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.string.*

type SemVerString = String :| SemanticVersion
object SemVerString extends RefinedTypeOps.Transparent[SemVerString]:
    extension (semVer: SemVerString)
        def asSemVer:SemVer = SemVer.unsafeParse(semVer)

    def unapply(input: String): Option[SemVer] = SemVer.parse(input).toOption