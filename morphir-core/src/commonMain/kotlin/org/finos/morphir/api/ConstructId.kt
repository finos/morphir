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
        public val boolean = ConstructIdentifier(
            scheme = "type",
            domain = Domains.Morphir,
            name = "boolean"
        )
        public val string = ConstructIdentifier(
            scheme = "type",
            domain = Domains.Morphir,
            name = "string"
        )
    }
}

