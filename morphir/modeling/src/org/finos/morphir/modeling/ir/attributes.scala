package org.finos.morphir.modeling.ir
import org.finos.morphir.modeling.Attributes
import org.finos.morphir.modeling.ConceptId

trait IRAttributes extends Attributes:
    def conceptId: ConceptId

trait TypeAttributes extends IRAttributes
object TypeAttributes:
    export Attributes.*

trait FunctionTypeAttributes extends TypeAttributes:
    def isCurried:Boolean

trait TypeSpecOrDefAttributes extends IRAttributes
object TypeSpecOrDefAttributes:
    export Attributes.*
