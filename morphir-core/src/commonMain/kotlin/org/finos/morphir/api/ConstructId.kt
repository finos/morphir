package org.finos.morphir.api

public sealed interface ConstructId {
    val scheme:String
    val domain: Domain
    val name: String
}

public data class ConstructIdentifier(
    override val scheme: String,
    override val domain: Domain,
    override val name: String
) : ConstructId

public data class UniversalConstructIdentifier(
    val distribution: List<String>,
    override val scheme: String,
    override val domain: Domain,
    override val name: String
) : ConstructId


public object KnownConstructIds {
    public object Primitives {
        public val boolean : ConstructId = primitiveConstructId("Boolean")

        public val int32 : ConstructId = primitiveConstructId("Int32")

        public val int64 : ConstructId = primitiveConstructId("Int64")

        public val localDate : ConstructId = primitiveConstructId("LocalDate")

        public val localDateTime: ConstructId = primitiveConstructId("LocalDateTime")

        public val string: ConstructId = primitiveConstructId("String")
    }
}

public fun primitiveConstructId(name: String): ConstructId {
    return ConstructIdentifier(
        scheme = "type",
        domain = Domains.Morphir,
        name = name
    )
}
