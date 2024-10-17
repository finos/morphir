package morphir.sdk

/// Type class for appending two values of the same type.
trait Appendable[A] {
  def append(a: A, b: A): A
}

object Appendable extends LowerPriorityAppendable {
  def apply[A](implicit appendable: Appendable[A]): Appendable[A] = appendable

  implicit val stringAppendable: Appendable[String] = new Appendable[String] {
    override def append(a: String, b: String): String = a + b
  }

  implicit def listAppendable[A]: Appendable[List[A]] = new Appendable[List[A]] {
    override def append(a: List[A], b: List[A]): List[A] = a ++ b
  }

  implicit def vectorAppendable[A]: Appendable[Vector[A]] = new Appendable[Vector[A]] {
    override def append(a: Vector[A], b: Vector[A]): Vector[A] = a ++ b
  }

  implicit def setAppendable[A]: Appendable[Set[A]] = new Appendable[Set[A]] {
    override def append(a: Set[A], b: Set[A]): Set[A] = a ++ b
  }
}

trait LowerPriorityAppendable {
  implicit def iterableAppendable[A]: Appendable[Iterable[A]] = new Appendable[Iterable[A]] {
    override def append(a: Iterable[A], b: Iterable[A]): Iterable[A] = a ++ b
  }
}
