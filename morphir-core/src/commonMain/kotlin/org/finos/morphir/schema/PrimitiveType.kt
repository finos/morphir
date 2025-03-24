package org.finos.morphir.schema

import org.finos.morphir.api.ConstructId
import org.finos.morphir.api.KnownConstructIds
import kotlin.Boolean as KBoolean
import kotlin.String as KString
import kotlinx.datetime.LocalDate as KLocalDate
import kotlinx.datetime.LocalDateTime as KLocalDateTime

public sealed interface PrimitiveType<out T>: IPrimitiveType {

    public data object Bool : PrimitiveType<KBoolean> {
        override val constructId: ConstructId = KnownConstructIds.Primitives.boolean
    }

    public data object Int32 : PrimitiveType<Int> {
        override val constructId: ConstructId = KnownConstructIds.Primitives.int32
    }

    public data object Int64 : PrimitiveType<Long> {
        override val constructId: ConstructId = KnownConstructIds.Primitives.int64
    }

    public data object LocalDate : PrimitiveType<KLocalDate> {
        override val constructId: ConstructId = KnownConstructIds.Primitives.localDate
    }

    public data object LocalDateTime: PrimitiveType<KLocalDateTime> {
        override val constructId: ConstructId = KnownConstructIds.Primitives.localDateTime
    }

    public data object String : PrimitiveType<KString> {
        override val constructId: ConstructId = KnownConstructIds.Primitives.string
    }
}

public sealed interface IPrimitiveType {
    val constructId: ConstructId
}
