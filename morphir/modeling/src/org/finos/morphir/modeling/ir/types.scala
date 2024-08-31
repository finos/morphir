package org.finos.morphir.modeling.ir
import org.finos.morphir.modeling.* 

sealed trait Type extends Element {
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
    final case class Function(parameters:IndexedSeq[Type], returnType:Type) extends Type:
        type Self = Function

    final case class Tuple(content:IndexedSeq[Type]) extends Type with IndexedTypeContainer[Type]:
        type Self = Tuple
        inline def elements:IndexedSeq[Type] = content
        
    final case class Unit() extends Type:
        type Self = Unit
    
    final case class Variable(name: Name, constraint:Constraint) extends Type:
        type Self = Variable
    object Variable:
        def apply(name: Name): Variable = Variable(name, Constraint.Any)

    enum Constraint:
        case Any
        case IsAssignableTo($type:Type)
        case IsAssignableFrom($type:Type)

type TypeVariable = Type.Variable
object TypeVariable:
    export Type.Variable.*