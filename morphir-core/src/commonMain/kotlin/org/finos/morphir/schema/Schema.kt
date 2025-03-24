package org.finos.morphir.schema


public sealed interface Schema<out T>: ISchema {
    //fun getType(name: String): Type
    public companion object {
        public val bool:Schema<Boolean> = primitive(PrimitiveType.Bool)
        public val int32:Schema<Int> = primitive(PrimitiveType.Int32)
        public val int64:Schema<Long> = primitive(PrimitiveType.Int64)
        public val string:Schema<String> = primitive(PrimitiveType.String)

        public fun <T> primitive(primitiveType: PrimitiveType<T>): Schema<T> =
            Primitive(primitiveType)

    }

    public data class Primitive<out T>(val primitiveType: PrimitiveType<T>) : Schema<T> {}
}

public sealed interface ISchema {}

fun dummy() {
    val boolSchema = Schema.bool
    val stringSchema = Schema.string
}

val Schema.Companion.boolean: Schema<Boolean> get ()= Schema.Companion.bool
val Schema.Companion.long: Schema<Long> get ()= Schema.Companion.int64