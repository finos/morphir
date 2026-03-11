package morphir.classic.ir

import kyo.Chunk

sealed trait Type[+A] extends Product with Serializable
object Type:
    final case class Variable[A](attributes: A, name: Name) extends Type[A]
    final case class Reference[A](attributes: A, fqname: FQName, args: Chunk[Type[A]]) extends Type[A]
    final case class Tuple[A](attributes: A, elements: Chunk[Type[A]]) extends Type[A]
    final case class Record[A](attributes: A, fields: Chunk[Field[A]]) extends Type[A]
    final case class ExtensibleRecord[A](attributes: A, variable: Name, fields: Chunk[Field[A]]) extends Type[A]
    final case class Function[A](attributes: A, arg: Type[A], result: Type[A]) extends Type[A]
    final case class Unit[A](attributes: A) extends Type[A]

    /**
      * Constructors in a dictionary keyed by their name. The values are the argument types for each constructor.
      */
    final case class Constructors[+A](items: Map[Name, ConstructorArgs[A]]) extends Product with Serializable:
        def names: Iterable[Name] = items.keys
        def constructorArgs: Iterable[ConstructorArgs[A]] = items.values
        def map[B](f: ConstructorArgs[A] => ConstructorArgs[B]): Constructors[B] = 
            Constructors(items.map(item => item._1 -> f(item._2)))
    /**
      * Represents a single constructor with a name and arguments.
      */
    final case class Constructor[+A](name: Name, args: ConstructorArgs[A]) extends Product with Serializable
    
    /**
      * Represents a list of constructor arguments.
      */
    final case class ConstructorArgs[+A](items: Chunk[(Name, Type[A])]) extends Product with Serializable:
        def names: Chunk[Name] = items.map(_._1)
        def types: Chunk[Type[A]] = items.map(_._2)
        def map[B](f: (Name, Type[A]) => (Name, Type[B])): ConstructorArgs[B] = 
            ConstructorArgs(items.map(item => f(item._1, item._2)))

    final case class Field[+A](name: Name, tpe: Type[A]) extends Product with Serializable
    object Field
end Type