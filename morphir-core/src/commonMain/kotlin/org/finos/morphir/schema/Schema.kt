package org.finos.morphir.schema

import org.finos.morphir.schema.ast.Type

public interface Schema {
    //fun getType(name: String): Type
    public companion object {
        public val bool:Schema = primitive(PrimitiveType.Bool)
        public val string:Schema = primitive(PrimitiveType.String)

        public fun primitive(primitiveType: PrimitiveType): Schema = Primitive(primitiveType)

    }

    public data class Primitive(val primitiveType: PrimitiveType) : Schema {}
}

fun dummy() {
    val boolSchema = Schema.bool
    val stringSchema = Schema.string
}
