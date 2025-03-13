package org.finos.morphir.msl.api

import org.finos.morphir.msl.ast.Type

public interface Schema {
    fun getType(name: String): Type
}