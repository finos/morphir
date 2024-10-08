package org.finos.morphir.ir.gen1

import org.finos.morphir.ir.gen1.naming.*
import org.finos.morphir.ir.gen1.Type.{Unit as UnitType, *}

trait TypeRewritingFolder[-Context, Attrib] extends TypeFolder[Context, Attrib, Type[Attrib]] {
  override def extensibleRecordCase(
    context: Context,
    tpe: Type[Attrib],
    attributes: Attrib,
    name: Name,
    fields: List[Field[Type[Attrib]]]
  ): Type[Attrib] =
    ExtensibleRecord(attributes, name, fields)

  override def functionCase(
    context: Context,
    tpe: Type[Attrib],
    attributes: Attrib,
    argumentType: Type[Attrib],
    returnType: Type[Attrib]
  ): Type[Attrib] =
    Function(attributes, argumentType, returnType)

  override def recordCase(
    context: Context,
    tpe: Type[Attrib],
    attributes: Attrib,
    fields: List[Field[Type[Attrib]]]
  ): Type[Attrib] =
    Record(attributes, fields)

  def referenceCase(
    context: Context,
    tpe: Type[Attrib],
    attributes: Attrib,
    typeName: FQName,
    typeParams: List[Type[Attrib]]
  ): Type[Attrib] =
    Reference(attributes, typeName, typeParams)

  def tupleCase(
    context: Context,
    tpe: Type[Attrib],
    attributes: Attrib,
    elements: List[Type[Attrib]]
  ): Type[Attrib] =
    Tuple(attributes, elements)

  def unitCase(context: Context, tpe: Type[Attrib], attributes: Attrib): Type[Attrib] = UnitType(attributes)

  def variableCase(context: Context, tpe: Type[Attrib], attributes: Attrib, name: Name): Type[Attrib] =
    Variable(attributes, name)
}
