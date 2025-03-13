package org.finos.morphir.api

public sealed interface ConstructId {
    val scheme:String
    val domain: List<String>
    val name: String
}

public data class ConstructIdentifier(
    override val scheme: String,
    override val domain: List<String>, override val name: String
) : ConstructId

public data class UniversalConstructIdentifier(
    val distribution: List<String>,
    override val scheme: String,
    override val domain: List<String>,
    override val name: String
) : ConstructId
