package org.finos.morphir.trees.ir
import org.finos.morphir.trees.Attributes
import org.finos.morphir.trees.ConceptId

// trait IRAttributes extends Attributes:
//     def conceptId: ConceptId

trait TypeSpecOrDefAttributes extends Attributes
object TypeSpecOrDefAttributes:
  export Attributes.*
