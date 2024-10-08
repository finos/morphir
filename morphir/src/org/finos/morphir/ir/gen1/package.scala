package org.finos.morphir.ir

import org.finos.morphir.ir.gen1.naming.*

import zio.=!=
import zio.prelude.*
import scala.annotation.nowarn

package object gen1 {
  type FieldK[+F[+_], +A] = Field[F[A]]
  object FieldK {
    def apply[F[+_], A](name: String, data: F[A]): FieldK[F, A] = Field(Name.fromString(name), data)
    def apply[F[+_], A](name: Name, data: F[A]): FieldK[F, A]   = Field(name, data)
  }

  type FieldT[+A] = FieldK[Type, A]
  object FieldT {
    def apply[A](name: String, tpe: Type[A]): FieldT[A] = FieldK(Name.fromString(name), tpe)
    def apply[A](name: Name, tpe: Type[A]): FieldT[A]   = FieldK(name, tpe)
  }

  type UType = Type[scala.Unit]
  final val UType: Type.type = Type

  type RawType = RawType.Type
  object RawType extends Subtype[Type[scala.Unit]]

  type RawTypeInfo = RawTypeInfo.Type
  object RawTypeInfo extends Subtype[TypeInfo[scala.Unit]] {
    def apply[A](typeInfo: TypeInfo[A])(implicit @nowarn ev: A =!= scala.Unit): RawTypeInfo =
      wrap(typeInfo.map(_ => ()))

  }
}
