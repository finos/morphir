package org.finos.morphir.modeling.ir
import org.finos.morphir.modeling.* 
import scala.collection.immutable.VectorMap

sealed trait TypeDescriptor extends Element {
  type Self <: TypeDescriptor
}

sealed trait ParameterizedTypeDescriptor extends TypeDescriptor {
  type Self <: ParameterizedTypeDescriptor
  def typeParams:List[Name]
}

sealed trait TypeExpression extends TypeDescriptor {
  type Self <: TypeExpression
}

sealed trait Type extends TypeExpression {
  type Self <: Type
}

trait TypeContainerBase[+T <: Type, +Col[+_]] extends ElementContainerBase[T, Col]
trait TypeContainer[T <: Type] extends TypeContainerBase[T, Seq] {
    type Self <: TypeContainer[T]
}

trait IndexedTypeContainer[T <: Type] extends TypeContainerBase[T, IndexedSeq] {
    inline def apply(index: Int): T = content(index)
}

object Type:   
    final case class Function(attributes:FunctionTypeAttributes, parameters:IndexedSeq[Type], returnType:Type) extends Type:
        type Self = Function
        type Attribs = FunctionTypeAttributes
    
    object Function:
        def apply(parameters:IndexedSeq[Type], returnType:Type): Function = Function(???, parameters, returnType)

    final case class Tuple(attributes:TypeAttributes, content:IndexedSeq[Type]) extends Type with IndexedTypeContainer[Type]:
        type Self = Tuple
        type Attribs = TypeAttributes
        inline def elements:IndexedSeq[Type] = content
        
    final case class Unit(attributes:TypeAttributes) extends Type:
        type Self = Unit
        type Attribs = TypeAttributes
    
    final case class Variable(attributes:TypeAttributes, name: Name, constraint:Constraint) extends Type:
        type Self = Variable
        type Attribs = TypeAttributes
    object Variable:
        def apply(name: Name): Variable = Variable(???, name, Constraint.Any)

    enum Constraint:
        case Any
        case IsAssignableTo($type:Type)
        case IsAssignableFrom($type:Type)

    final case class ConstructorArgs(toMap:VectorMap[Name, Type])
    final case class Constructor(name:Name, args:ConstructorArgs)
    final case class Constructors(toMap:Map[Name, ConstructorArgs])

type TypeVariable = Type.Variable
object TypeVariable:
    export Type.Variable.*

sealed trait TypeSpecification extends ParameterizedTypeDescriptor {
    type Self <: TypeSpecification
}

object TypeSpecification:
    final case class TypeAliasSpecification(attributes:TypeAttributes, typeParams: List[Name], typeExpr:Type) extends TypeSpecification:
        type Self = TypeAliasSpecification
        type Attribs = TypeAttributes

    final case class OpaqueTypeSpecification(attributes:TypeAttributes, typeParams:List[Name]) extends TypeSpecification:
        type Self = OpaqueTypeSpecification
        type Attribs = TypeAttributes
    
    final case class CustomTypeSpecification(attributes:TypeAttributes, typeParams:List[Name]) extends TypeSpecification:
        type Self = CustomTypeSpecification
        type Attribs = TypeAttributes
    object CustomTypeSpecification

    type EnumTypeSpecification = CustomTypeSpecification
    object EnumTypeSpecification:
        export CustomTypeSpecification.*

sealed trait TypeDefinition extends ParameterizedTypeDescriptor:
    type Self <: TypeDefinition
    type Attribs <: TypeSpecOrDefAttributes


object TypeDefinition:
    final case class TypeAliasDefinition(
        attributes:TypeSpecOrDefAttributes,
        typeParams:List[Name], 
        typeExpr:Type, 
        flags:Option[Flags]
    ) extends TypeDefinition:
        type Self = TypeAliasDefinition
        type Attribs = TypeSpecOrDefAttributes


type TypeAlias = TypeDefinition.TypeAliasDefinition
object TypeAlias:
    export TypeDefinition.TypeAliasDefinition.*