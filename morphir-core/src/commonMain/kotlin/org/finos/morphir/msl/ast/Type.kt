package org.finos.morphir.msl.ast

import org.finos.morphir.api.ConstructId
import org.finos.morphir.mdl.ast.MorphirValue

public interface Type {
    public val name: String?
    public val constructId: ConstructId
    public val msl: MorphirValue
}