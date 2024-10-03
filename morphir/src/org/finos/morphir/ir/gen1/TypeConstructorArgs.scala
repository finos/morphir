package org.finos.morphir.ir.gen1

final case class TypeConstructorArgs[+A](args: List[TypeConstructorArg[A]]) extends AnyVal { self =>
  def map[B](f: A => B): TypeConstructorArgs[B] = TypeConstructorArgs(self.args.map(_.map(f)))
  def toList: List[TypeConstructorArg[A]]       = args
}

object TypeConstructorArgs {
  implicit def toList[A](args: TypeConstructorArgs[A]): List[TypeConstructorArg[A]] = args.args
}
