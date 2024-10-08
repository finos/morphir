package org.finos.morphir.ir.gen1

import org.finos.morphir.ir.gen1.naming.*

final case class TypeConstructor[+A](name: Name, args: TypeConstructorArgs[A]) {
  def map[B](f: A => B): TypeConstructor[B] = copy(args = args.map(f))
}
