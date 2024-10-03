package org.finos.morphir.ir.gen1

sealed trait TypeInfo[+A] { self =>
  def map[B](f: A => B): TypeInfo[B] = self match {
    case TypeInfo.TypeExpr(info) => TypeInfo.TypeExpr(info.map(f))
    case TypeInfo.TypeSpec(info) => TypeInfo.TypeSpec(info.map(f))
    case TypeInfo.TypeDef(info)  => TypeInfo.TypeDef(info.map(f))
  }
}

object TypeInfo {

  def typeExpr[A](value: Type[A]): TypeInfo[A]              = TypeExpr(value)
  def typeSpec[A](value: TypeSpecification[A]): TypeInfo[A] = TypeSpec(value)
  def typeDef[A](value: TypeDefinition[A]): TypeInfo[A]     = TypeDef(value)

  final case class TypeExpr[+A](info: Type[A])              extends TypeInfo[A]
  final case class TypeSpec[+A](info: TypeSpecification[A]) extends TypeInfo[A]
  final case class TypeDef[+A](info: TypeDefinition[A])     extends TypeInfo[A]
}
