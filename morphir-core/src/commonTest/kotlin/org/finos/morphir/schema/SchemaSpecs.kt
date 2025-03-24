package org.finos.morphir.schema
import io.kotest.core.spec.style.WordSpec
import io.kotest.matchers.*
import io.kotest.matchers.nulls.shouldNotBeNull

class SchemaSpecs: WordSpec({

    "Schema.bool" should {
        "not be null" {
            val boolSchema = Schema.bool
            boolSchema.shouldNotBeNull()
        }
    }
})