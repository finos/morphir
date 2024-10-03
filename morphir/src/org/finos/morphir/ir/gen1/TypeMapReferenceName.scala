package org.finos.morphir.ir.gen1

import org.finos.morphir.ir.gen1.naming.*
import org.finos.morphir.ir.gen1.Type.{Unit as UnitType, *}

final case class TypeMapReferenceName[Attrib](f: FQName => FQName) extends TypeRewritingFolder[Any, Attrib] {
  override def referenceCase(
    context: Any,
    tpe: Type[Attrib],
    attributes: Attrib,
    typeName: FQName,
    typeParams: List[Type[Attrib]]
  ): Type[Attrib] =
    Reference(attributes, f(typeName), typeParams)

}
