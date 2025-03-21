package org.finos.morphir.api

public data class Domain(val segments:List<String>){
    public val name: String = segments.joinToString(".")

    override fun toString(): String = name
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is Domain) return false

        if (name != other.name) return false

        return true
    }
    override fun hashCode(): Int {
        return name.hashCode()
    }
}

public object Domains {
    public val Morphir = domainOf("morphir")
    public val MorphirSchema = domainOf("morphir", "schema")
    public val MorphirSchemaPrimitive = domainOf("morphir", "schema", "primitive")
}

public fun domainOf(vararg segments: String): Domain {
    return Domain(segments.toList())
}