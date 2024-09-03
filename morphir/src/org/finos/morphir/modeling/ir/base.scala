package org.finos.morphir.modeling.ir
import org.finos.morphir.modeling.Attributes
import org.finos.morphir.modeling.ConceptId

// trait IRAttributes extends Attributes:
//     def conceptId: ConceptId

trait TypeSpecOrDefAttributes extends Attributes
object TypeSpecOrDefAttributes:
  export Attributes.*
