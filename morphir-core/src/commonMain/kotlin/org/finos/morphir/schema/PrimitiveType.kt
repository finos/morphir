package org.finos.morphir.schema

import org.finos.morphir.api.ConstructId
import org.finos.morphir.api.KnownConstructIds

public interface PrimitiveType {
    val constructId: ConstructId

    public data object Bool : PrimitiveType {
        override val constructId: ConstructId = KnownConstructIds.Primitives.boolean
    }

    public data object String : PrimitiveType {
        override val constructId: ConstructId = KnownConstructIds.Primitives.string
    }
}
