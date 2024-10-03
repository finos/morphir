package org.finos.morphir.ir.gen1

import org.finos.morphir.ir.gen1.naming.*

sealed trait TypeSpecification[+A] { self =>
  import TypeSpecification.*

  final def properties: Properties[A] =
    self match {
      case TypeAliasSpecification(_, expr)              => Properties.TypeAlias(expr)
      case CustomTypeSpecification(_, ctors)            => Properties.CustomType(ctors)
      case DerivedTypeSpecification(_, derivationProps) => derivationProps
      case OpaqueTypeSpecification(_)                   => Properties.OpaqueType
    }

  final def map[B](f: A => B): TypeSpecification[B] =
    self match {
      case spec @ TypeAliasSpecification(_, _)  => TypeAliasSpecification(spec.typeParams, spec.expr.map(f))
      case spec @ OpaqueTypeSpecification(_)    => spec
      case spec @ CustomTypeSpecification(_, _) => spec.copy(ctors = spec.ctors.map(f))
      case spec @ DerivedTypeSpecification(_, _) =>
        val baseType = spec.derivationProps.baseType.map(f)
        val props    = spec.derivationProps.copy(baseType = baseType)
        spec.copy(derivationProps = props)
    }

  def typeParams: List[Name]

}

object TypeSpecification {
  final case class TypeAliasSpecification[+A](typeParams: List[Name], expr: Type[A]) extends TypeSpecification[A]
  final case class OpaqueTypeSpecification(typeParams: List[Name])                   extends TypeSpecification[Nothing]
  final case class CustomTypeSpecification[+A](typeParams: List[Name], ctors: TypeConstructors[A])
      extends TypeSpecification[A]

  final case class DerivedTypeSpecification[+A](typeParams: List[Name], derivationProps: Properties.DerivedType[A])
      extends TypeSpecification[A]

  sealed trait Properties[+A] { self =>
    def map[B](f: A => B): Properties[B] =
      self match {
        case props @ Properties.TypeAlias(_)         => Properties.TypeAlias(props.expr.map(f))
        case props @ Properties.CustomType(_)        => props.copy(ctors = props.ctors.map(f))
        case props @ Properties.DerivedType(_, _, _) => props.copy(baseType = props.baseType.map(f))
        case _                                       => Properties.OpaqueType
      }
  }

  object Properties {
    final case class TypeAlias[+A](expr: Type[A]) extends Properties[A]
    type OpaqueType = Properties.OpaqueType.type
    case object OpaqueType extends Properties[Nothing] {
      type Type[+A] = Properties.OpaqueType.type
    }
    final case class CustomType[+A](ctors: TypeConstructors[A]) extends Properties[A]
    final case class DerivedType[+A](baseType: Type[A], fromBaseType: FQName, toBaseType: FQName)
        extends Properties[A]
  }
}
