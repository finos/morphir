package org.finos.morphir.ir.gen1

import org.finos.morphir.ir.gen1.*
import org.finos.morphir.ir.gen1.Type.{Unit as UnitType, *}

import scala.annotation.{tailrec, unused}
import zio.prelude.*
import zio.Task

sealed trait TypeExpr { self =>
  def attributes: Any
  def tag: Int
}

sealed trait Type[+A] extends TypeExpr { self =>
  import Type.{Unit as UnitType, *}
  type AttributesType <: A

  def ??(doc: String): Documented[Type[A]] = Documented(doc, this)

  override def attributes: A

  final def collectReferences: Set[FQName] = foldDownSome(Set.empty[FQName]) {
    case (acc, Reference(_, typeName, _)) => acc + typeName
    case (acc, _)                         => acc
  }

  final def collectVariables: Set[Name] = foldDownSome(Set.empty[Name]) {
    case (acc, Variable(_, name)) => acc + name
    case (acc, _)                 => acc
  }

  final def eraseAttributes: UType = self.mapAttributes(_ => ())

  final def exists(f: PartialFunction[Type[A], Any]): Boolean = find(f).isDefined

  final def find[Z](f: PartialFunction[Type[A], Z]): Option[Z] = {
    @tailrec
    def loop(typ: Type[A], stack: List[Type[A]]): Option[Z] =
      f.lift(typ) match {
        case Some(z) => Some(z)
        case None =>
          typ match {
            case ExtensibleRecord(_, _, head :: tail) =>
              val next = head.data
              val rest = tail.map(_.data) ++: stack
              loop(next, rest)
            case Function(_, argumentType, resultType) =>
              loop(argumentType, resultType :: stack)
            case Record(_, List(head, tail @ _*)) =>
              val next = head.data
              val rest = tail.map(_.data) ++: stack
              loop(next, rest)
            case Reference(_, _, List(head, tail @ _*)) =>
              loop(head, tail ++: stack)
            case Tuple(_, List(head, tail @ _*)) =>
              loop(head, tail ++: stack)
            case _ =>
              stack match {
                case head :: tail => loop(head, tail)
                case Nil          => None
              }
          }
      }

    loop(self, Nil)
  }

  def findAll[Z](f: PartialFunction[Type[A], Z]): List[Z] = foldDownSome[List[Z]](Nil) {
    case (acc, typ) if f.isDefinedAt(typ) => f(typ) :: acc
    case (acc, _)                         => acc
  }

  lazy val fieldCount: Int = foldDownSome[Int](0) {
    case (acc, Record(_, fields))              => acc + fields.size
    case (acc, ExtensibleRecord(_, _, fields)) => acc + fields.size
    case (acc, _)                              => acc
  }

  final def foldDown[Z](z: Z)(f: (Z, Type[A]) => Z): Z = {

    @tailrec
    def loop(remaining: List[Type[A]], acc: Z): Z = remaining match {
      case Nil => acc
      case head :: tail => head match {
          case e: ExtensibleRecord[A] =>
            loop(e.fields.map(_.data).view.toList ++ tail, f(acc, e))

          case fun: Function[A] =>
            loop(fun.argumentType :: fun.returnType :: tail, f(acc, fun))

          case rec: Record[A] =>
            loop(rec.fields.map(_.data).view.toList ++ tail, f(acc, rec))

          case ref: Reference[A] =>
            loop(ref.typeParams.view.toList ++ tail, f(acc, ref))

          case t: Tuple[A] =>
            loop(t.elements.view.toList ++ tail, f(acc, t))

          case u: UnitType[A] =>
            loop(tail, f(acc, u))

          case v: Variable[A] =>
            loop(tail, f(acc, v))
        }
    }

    loop(List(this), z)
  }

  final def foldDownSome[Z](z: Z)(f: PartialFunction[(Z, Type[A]), Z]): Z = {

    @tailrec
    def loop(remaining: List[Type[A]], acc: Z): Z = remaining match {
      case Nil => acc
      case head :: tail =>
        val newAcc = if (f.isDefinedAt((acc, head))) f((acc, head)) else acc
        head match {
          case ExtensibleRecord(_, _, fields) =>
            loop(fields.map(_.data) ++ tail, newAcc)

          case Function(_, argumentType, returnType) =>
            loop(argumentType :: returnType :: tail, newAcc)

          case Record(_, fields) =>
            loop(fields.map(_.data) ++ tail, newAcc)

          case Reference(_, _, typeParams) =>
            loop(typeParams ++ tail, newAcc)

          case Tuple(_, elements) =>
            loop(elements ++ tail, newAcc)

          // The following
          case UnitType(_) =>
            loop(tail, newAcc)

          case Variable(_, _) =>
            loop(tail, newAcc)
        }
    }

    loop(List(this), z)
  }

  final def foldLeft[Z](z: Z)(f: (Z, A) => Z): Z = foldDown(z) {
    case (acc, typ) => f(acc, typ.attributes)
  }

  final def foldLeftSome[Z](z: Z)(f: PartialFunction[(Z, A), Z]): Z = foldDownSome(z) {
    case (acc, typ) => f((acc, typ.attributes))
  }

  final def foldRight[Z](z: Z)(f: (A, Z) => Z): Z = foldUp(z) {
    case (typ, acc) => f(typ.attributes, acc)
  }

  final def foldUp[Z](z: Z)(f: (Type[A], Z) => Z): Z = {
    val stack = collection.mutable.Stack[Type[A]](this)
    var acc   = z
    while (stack.nonEmpty) {
      val current = stack.pop()
      current match {
        case e @ ExtensibleRecord(_, _, _) =>
          stack.pushAll(e.fields.map(_.data))

        case fun @ Function(_, _, _) =>
          stack.push(fun.argumentType, fun.returnType)

        case rec @ Record(_, _) =>
          stack.pushAll(rec.fields.map(_.data))

        case ref: Reference[A] =>
          stack.pushAll(ref.typeParams)

        case t @ Tuple(_, _) =>
          stack.pushAll(t.elements)
        case UnitType(_) =>
          ()
        case Variable(_, _) =>
          ()
      }
      acc = f(current, acc)
    }
    acc
  }

  final def foldUpSome[Z](z: Z)(f: PartialFunction[(Type[A], Z), Z]): Z = {
    val stack = collection.mutable.Stack[Type[A]](this)
    var acc   = z
    while (stack.nonEmpty) {
      val current = stack.pop()
      current match {
        case e @ ExtensibleRecord(_, _, _) =>
          stack.pushAll(e.fields.map(_.data))

        case fun @ Function(_, _, _) =>
          stack.push(fun.argumentType, fun.returnType)

        case rec @ Record(_, _) =>
          stack.pushAll(rec.fields.map(_.data))

        case ref: Reference[A] =>
          stack.pushAll(ref.typeParams)

        case t @ Tuple(_, _) =>
          stack.pushAll(t.elements)
        case UnitType(_) =>
          ()
        case Variable(_, _) =>
          ()
      }
      if (f.isDefinedAt((current, acc)))
        acc = f((current, acc))
    }
    acc
  }

  def fold[A1 >: A](z: A1)(f: (A1, A1) => A1): A1 = foldLeft(z)(f)

  def fold[Z](
    unitCase0: A => Z,
    variableCase0: (A, Name) => Z,
    extensibleRecordCase0: (A, Name, List[Field[Z]]) => Z,
    functionCase0: (A, Z, Z) => Z,
    recordCase0: (A, List[Field[Z]]) => Z,
    referenceCase0: (A, FQName, List[Z]) => Z,
    tupleCase0: (A, List[Z]) => Z
  ): Z = TypeFolder.foldContext[Any, A, Z](self, ())(
    new TypeFolder[Any, A, Z] {
      def unitCase(context: Any, tpe: Type[A], attributes: A): Z = unitCase0(attributes)

      def variableCase(context: Any, tpe: Type[A], attributes: A, name: Name): Z = variableCase0(attributes, name)

      def extensibleRecordCase(context: Any, tpe: Type[A], attributes: A, name: Name, fields: List[Field[Z]]): Z =
        extensibleRecordCase0(attributes, name, fields)

      def functionCase(context: Any, tpe: Type[A], attributes: A, argumentType: Z, returnType: Z): Z =
        functionCase0(attributes, argumentType, returnType)

      def recordCase(context: Any, tpe: Type[A], attributes: A, fields: List[Field[Z]]): Z =
        recordCase0(attributes, fields)

      def referenceCase(context: Any, tpe: Type[A], attributes: A, typeName: FQName, typeParams: List[Z]): Z =
        referenceCase0(attributes, typeName, typeParams)

      def tupleCase(context: Any, tpe: Type[A], attributes: A, elements: List[Z]): Z =
        tupleCase0(attributes, elements)
    }
  )

  final def foldContext[C, A1 >: A, Z](context: C)(folder: TypeFolder[C, A1, Z]): Z =
    TypeFolder.foldContext(self, context)(folder)

  /// Tells if a type is an intrinsic type or if it is a user-defined type.
  final def isIntrinsic: Boolean = self match {
    case Reference(_, _, _) => false
    case _                  => true
  }

  /// Tells if the type is a reference to a type.
  final def isReference: Boolean = self match {
    case Reference(_, _, _) => true
    case _                  => false
  }

  def mapAttributes[B](f: A => B): Type[B] = {
    sealed trait ProcessTask
    case class Process[T >: Type[A]](node: T, processedChildren: List[Type[B]]) extends ProcessTask

    @scala.annotation.tailrec
    def loop(stack: List[ProcessTask], accumulator: List[Type[B]]): Type[B] = stack match {
      case Nil => accumulator.head
      case Process(node, children) :: tail => node match {
          case e @ ExtensibleRecord(_, _, _) if children.length < e.fields.length =>
            loop(Process(e.fields(children.length).data, Nil) :: stack, accumulator)
          case e @ ExtensibleRecord(_, _, _) =>
            val newFields = children.takeRight(e.fields.length).map(t => FieldT(t.asInstanceOf[FieldT[B]].name, t))
            loop(tail, ExtensibleRecord(f(e.attributes.asInstanceOf[A]), e.name, newFields.reverse) :: accumulator)

          case fun @ Function(_, _, _) if children.isEmpty =>
            loop(Process(fun.argumentType, Nil) :: stack, accumulator)
          case fun @ Function(_, _, _) if children.length == 1 =>
            loop(Process(fun.returnType, Nil) :: stack, accumulator)
          case fun @ Function(_, _, _) =>
            loop(tail, Function(f(fun.attributes.asInstanceOf[A]), children(1), children.head) :: accumulator)

          case rec @ Record(_, _) if children.length < rec.fields.length =>
            loop(Process(rec.fields(children.length).data, Nil) :: stack, accumulator)
          case rec @ Record(_, _) =>
            val newFields = children.takeRight(rec.fields.length).map(t => FieldT(t.asInstanceOf[FieldT[B]].name, t))
            loop(tail, Record(f(rec.attributes.asInstanceOf[A]), newFields.reverse) :: accumulator)

          case ref @ Reference(_, _, _) if children.length < ref.typeParams.length =>
            loop(Process(ref.typeParams(children.length), Nil) :: stack, accumulator)
          case ref @ Reference(_, _, _) =>
            loop(tail, Reference(f(ref.attributes.asInstanceOf[A]), ref.typeName, children.reverse) :: accumulator)

          case t @ Tuple(_, _) if children.length < t.elements.length =>
            loop(Process(t.elements(children.length), Nil) :: stack, accumulator)
          case t @ Tuple(_, _) =>
            loop(tail, Tuple(f(t.attributes.asInstanceOf[A]), children.reverse) :: accumulator)

          case u @ UnitType(_) =>
            loop(tail, UnitType(f(u.attributes.asInstanceOf[A])) :: accumulator)

          case v @ Variable(_, _) =>
            loop(tail, Variable(f(v.attributes.asInstanceOf[A]), v.name) :: accumulator)
        }
    }

    loop(List(Process(this, Nil)), Nil)
  }

  final def map[B](f: A => B): Type[B] =
    fold[Type[B]](
      attributes => UnitType(f(attributes)),
      (attributes, name) => Variable(f(attributes), name),
      (attributes, name, fields) => ExtensibleRecord(f(attributes), name, fields.asInstanceOf[List[FieldT[B]]]),
      (attributes, argumentType, returnType) => Function(f(attributes), argumentType, returnType),
      (attributes, fields) => Record(f(attributes), fields.asInstanceOf[List[FieldT[B]]]),
      (attributes, typeName, typeParams) => Reference(f(attributes), typeName, typeParams),
      (attributes, elements) => Tuple(f(attributes), elements)
    )

  lazy val size: Long = foldLeft(0L) {
    case (acc, _) => acc + 1
  }

  def tag: Int

  override def toString: String = foldContext(())(TypeFolder.ToString)

  // final def transformDownSome[A1 >: A](f: PartialFunction[Type[A1], Type[A1]]): Type[A1] = {
  //   def loop(stack:List[Type[A]],):Type[A1] =
  // }

  final def satisfies(check: PartialFunction[Type[A], Boolean]): Boolean =
    check.lift(self).getOrElse(false)

  /** Uses the specified function to map the FQName of any type references to another FQName.
    */
  final def transformReferenceName(f: FQName => FQName): Type[A] = foldContext(())(TypeMapReferenceName(f))

  // TODOD: Support writing throw a writer visitor
  // def write[Context](context: Context)(writer: TypeWriter[Context, A]): Unit =
  //   self match {
  //     case ExtensibleRecord(_, _, _)  => ???
  //     case Function(_, _, _)          => ???
  //     case Record(_, _)               => ???
  //     case Reference(_, _, _)         => ???
  //     case Tuple(_, _)                => ???
  //     case UnitType(attributes)       => writer.writeUnit(context, attributes)
  //     case Variable(attributes, name) => writer.writeVariable(context, attributes, name)
  //   }

  // def writeZIO[Context: Tag](writer: TypeWriter[Context, A]): ZIO[Context, Throwable, Unit] =
  //   self match {
  //     case ExtensibleRecord(_, _, _)  => ???
  //     case Function(_, _, _)          => ???
  //     case Record(_, _)               => ???
  //     case Reference(_, _, _)         => ???
  //     case Tuple(_, _)                => ???
  //     case UnitType(attributes)       => writer.writeUnitZIO(attributes)
  //     case Variable(attributes, name) => writer.writeVariableZIO(attributes, name)
  //   }
}

object Type {

  def mapTypeAttributes[A](tpe: Type[A]): MapTypeAttributes[A] = new MapTypeAttributes(() => tpe)

  object Attributes {
    def unapply[A](typ: Type[A]): Some[A] = Some(typ.attributes)
  }

  sealed case class ExtensibleRecord[+A](attributes: A, name: Name, fields: List[FieldT[A]]) extends Type[A] {
    override def tag: Int = Tags.ExtensibleRecord
  }

  object ExtensibleRecord {
    def apply[A](attributes: A, name: String, fields: List[FieldT[A]]): ExtensibleRecord[A] =
      ExtensibleRecord(attributes, Name.fromString(name), fields)

    def apply[A](attributes: A, name: String, fields: FieldT[A]*): ExtensibleRecord[A] =
      ExtensibleRecord(attributes, Name.fromString(name), fields.toList)

    def apply[A](attributes: A, name: Name, fields: FieldT[A]*): ExtensibleRecord[A] =
      ExtensibleRecord(attributes, name, fields.toList)
  }

  sealed case class Function[+A](attributes: A, argumentType: Type[A], returnType: Type[A]) extends Type[A] {
    override def tag: Int = Tags.Function
  }

  sealed case class Record[+A](attributes: A, fields: List[FieldT[A]]) extends Type[A] {
    override def tag: Int = Tags.Record
  }
  object Record {
    def apply[A](attributes: A, fields: FieldT[A]*): Record[A] = Record(attributes, fields.toList)
  }

  sealed case class Reference[+A](attributes: A, typeName: FQName, typeParams: List[Type[A]]) extends Type[A] {
    override def tag: Int = Tags.Reference
  }

  object Reference {
    def apply[A](attributes: A, typeName: String, typeParams: List[Type[A]]): Reference[A] =
      Reference(attributes, FQName.fromString(typeName), typeParams)

    def apply[A](attributes: A, typeName: String, typeParams: Type[A]*): Reference[A] =
      Reference(attributes, FQName.fromString(typeName), typeParams.toList)

    def apply[A](attributes: A, typeName: FQName, typeParams: Type[A]*): Reference[A] =
      Reference(attributes, typeName, typeParams.toList)
  }

  sealed case class Tuple[+A](attributes: A, elements: List[Type[A]]) extends Type[A] {
    override def tag: Int = Tags.Tuple
  }
  object Tuple {
    def apply[A](attributes: A, elements: Type[A]*): Tuple[A] = Tuple(attributes, elements.toList)
  }
  sealed case class Unit[+A](attributes: A) extends Type[A] {
    override def tag: Int = Tags.Unit
  }
  sealed case class Variable[+A](attributes: A, name: Name) extends Type[A] {
    override def tag: Int = Tags.Variable
  }
  object Variable {
    def apply[A](attributes: A, name: String): Variable[A] = Variable(attributes, Name.fromString(name))
    def apply(name: Name): Variable[scala.Unit]            = Variable((), name)
    def apply(name: String): Variable[scala.Unit]          = Variable((), name)
  }

  implicit val CovariantTypeInstance: Covariant[Type] = new Covariant[Type] {
    def map[A, B](f: A => B): Type[A] => Type[B] = _.map(f)
  }

  private object Tags {
    final val ExtensibleRecord = 0
    final val Function         = 1
    final val Record           = 2
    final val Reference        = 3
    final val Tuple            = 4
    final val Unit             = 5
    final val Variable         = 6
  }

  private[Type] type Process[+A, +Z] = (Type[A], List[Z])

  private[Type] object Process {
    def apply[A, Z](tpe: Type[A], children: List[Z]): Process[A, Z]       = (tpe, Nil)
    def unapply[A, Z](process: Process[A, Z]): Option[(Type[A], List[Z])] = Some(process)

  }
  trait ForEachZIO[-Context, -Attrib] extends TypeFolder[Context, Attrib, Task[scala.Unit]] {}

  implicit val CovariantType: Covariant[Type] = new Covariant[Type] {
    override def map[A, B](f: A => B): Type[A] => Type[B] = tpe => tpe.mapAttributes(f)
  }

  final class MapTypeAttributes[+A](val input: () => Type[A]) {
    def apply[B](f: A => B): Type[B] = input().map(f)
  }

  implicit class UTypeExtensions(private val self: UType) {
    def -->(that: UType): UType = Type.Function((), self, that)
  }
}

object TypeVisitorUsage {
  // val visitor = TypeVisitor.stateful(()) {
  //   case Type.Unit(_) => ???
  //   case _            => ???
  // }

  // visitor[scala.Unit](Type.Unit(()))
}
