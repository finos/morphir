/*
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
 */

package morphir.sdk

import scala.util.{ Failure, Success, Try }

object Maybe {

  sealed abstract class Maybe[+A] extends MaybeLike[A] { self =>

    def get: A

    @inline final def getOrElse[B >: A](default: => B): B =
      if (isEmpty) default else this.get

    @SuppressWarnings(
      Array(
        "scalafix:DisableSyntax.null"
      )
    )
    @inline final def orNull[A1 >: A](implicit ev: Null <:< A1): A1 =
      this getOrElse ev(null)

    def isEmpty: Boolean   = this eq Nothing
    def isDefined: Boolean = !isEmpty

    @inline final def fold[B](ifEmpty: => B)(f: A => B): B =
      if (isEmpty) ifEmpty else f(this.get)

    def map[B](fn: A => B): Maybe[B]

    @inline final def filter(p: A => Boolean): Maybe[A] =
      if (isEmpty || p(this.get)) this else Nothing

    @inline final def filterNot(p: A => Boolean): Maybe[A] =
      if (isEmpty || !p(this.get)) this else None

    def flatMap[B](fn: A => Maybe[B]): Maybe[B]

    def flatten[B](implicit ev: A <:< Maybe[B]): Maybe[B] =
      if (isEmpty) None else ev(this.get)

    def withFilter(fn: A => Boolean): WithFilter = new WithFilter((fn))

    /** We need a whole WithFilter class to honor the "doesn't create a new collection" contract even though it seems
      * unlikely to matter much in a collection with max size 1.
      */
    class WithFilter(p: A => Boolean) {
      def map[B](f: A => B): Maybe[B] = self filter p map f
      def flatMap[B](f: A => Maybe[B]): Maybe[B] =
        self filter p flatMap f
      def foreach[U](f: A => U): Unit = self filter p foreach f
      def withFilter(q: A => Boolean): WithFilter =
        new WithFilter(x => p(x) && q(x))
    }

    @inline final def foreach[U](f: A => U): Unit = {
      if (!isEmpty) {
        val _ = f(this.get)
        ()
      }

      ()
    }

    final def contains[A1 >: A](elem: A1): Boolean =
      !isEmpty && this.get == elem

    @inline final def exists(p: A => Boolean): Boolean =
      !isEmpty && p(this.get)

    @inline final def forall(p: A => Boolean): Boolean = isEmpty || p(this.get)

    @inline final def collect[B](pf: PartialFunction[A, B]): Maybe[B] =
      if (!isEmpty) pf.lift(this.get) else None

    @inline final def orElse[B >: A](
      alternative: => Maybe[B]
    ): Maybe[B] =
      if (isEmpty) alternative else this

    final def nonEmpty: Boolean = isDefined

    final def zip[A1 >: A, B](that: Maybe[B]): Maybe[(A1, B)] =
      if (isEmpty || that.isEmpty) Nothing else Just((this.get, that.get))

    final def unzip[A1, A2](implicit
      asPair: A <:< (A1, A2)
    ): (Maybe[A1], Maybe[A2]) =
      if (isEmpty)
        (Nothing, Nothing)
      else {
        val e = asPair(this.get)
        (Just(e._1), Just(e._2))
      }

    def iterator: Iterator[A] =
      if (isEmpty) collection.Iterator.empty
      else collection.Iterator.single(this.get)

    def toList: List[A] =
      if (isEmpty) List() else new ::(this.get, Nil)

    @inline final def toRight[X](left: => X): Either[X, A] =
      if (isEmpty) Left(left) else Right(this.get)

    @inline final def toLeft[X](right: => X): Either[A, X] =
      if (isEmpty) Right(right) else Left(this.get)

    def asOption: Option[A]
  }

  case class Just[+A](value: A) extends Maybe[A] {
    def get: A = value

    def map[B](fn: A => B): Maybe[B] = Just(fn(value))

    def flatMap[B](fn: A => Maybe[B]): Maybe[B] = fn(value)

    def asOption: Option[A] = Some(value)
  }

  case object Nothing extends Maybe[scala.Nothing] {

    def get: scala.Nothing = throw new NoSuchElementException("Nothing.get") // scalafix:ok

    def map[B](fn: scala.Nothing => B): Maybe[B] = this

    def flatMap[B](fn: scala.Nothing => Maybe[B]): Maybe[B] =
      Nothing

    def asOption: Option[scala.Nothing] = None
  }

  val nothing: Maybe[scala.Nothing] = Nothing

  def just[A](value: A): Maybe[A] = Some(value)
  def empty[A]: Maybe[A]          = Nothing

  def map[A, A1](fn: A => A1)(maybe: Maybe[A]): Maybe[A1] =
    maybe match {
      case Just(a) => Just(fn(a))
      case _       => Nothing.asInstanceOf[Maybe[A1]]
    }

  def map2[A, B, V](
    fn: A => B => V
  )(maybeA: Maybe[A])(maybeB: Maybe[B]): Maybe[V] =
    (maybeA, maybeB) match {
      case (Just(a), Just(b)) => Just(fn(a)(b))
      case _                  => Nothing.asInstanceOf[Maybe[V]]
    }

  def map3[A, B, C, V](
    fn: A => B => C => V
  ): Maybe[A] => Maybe[B] => Maybe[C] => Maybe[
    V
  ] =
    (maybeA: Maybe[A]) =>
      (maybeB: Maybe[B]) =>
        (maybeC: Maybe[C]) =>
          (maybeA, maybeB, maybeC) match {
            case (Just(a), Just(b), Just(c)) => Just(fn(a)(b)(c))
            case _                           => Nothing.asInstanceOf[Maybe[V]]
          }

  def map4[A, B, C, D, V](
    fn: A => B => C => D => V
  ): Maybe[A] => Maybe[B] => Maybe[C] => Maybe[
    D
  ] => Maybe[V] =
    (maybeA: Maybe[A]) =>
      (maybeB: Maybe[B]) =>
        (maybeC: Maybe[C]) =>
          (maybeD: Maybe[D]) =>
            (maybeA, maybeB, maybeC, maybeD) match {
              case (Just(a), Just(b), Just(c), Just(d)) => Just(fn(a)(b)(c)(d))
              case _                                    => Nothing.asInstanceOf[Maybe[V]]
            }

  def map5[A, B, C, D, E, V](
    fn: A => B => C => D => E => V
  ): Maybe[A] => Maybe[B] => Maybe[C] => Maybe[
    D
  ] => Maybe[E] => Maybe[V] =
    (maybeA: Maybe[A]) =>
      (maybeB: Maybe[B]) =>
        (maybeC: Maybe[C]) =>
          (maybeD: Maybe[D]) =>
            (maybeE: Maybe[E]) =>
              (maybeA, maybeB, maybeC, maybeD, maybeE) match {
                case (Just(a), Just(b), Just(c), Just(d), Just(e)) =>
                  Just(fn(a)(b)(c)(d)(e))
                case _ => Nothing.asInstanceOf[Maybe[V]]
              }

  def andThen[A, B](
    fn: A => Maybe[B]
  )(maybeA: Maybe[A]): Maybe[B] =
    maybeA match {
      case Just(value) => fn(value)
      case Nothing     => Nothing.asInstanceOf[Maybe[B]]
    }

  def withDefault[A, A1 >: A](
    defaultValue: A1
  )(maybeValue: Maybe[A]): A1 =
    maybeValue match {
      case _: Maybe.Nothing.type => defaultValue
      case Just(value)           => value
    }

  implicit def toOption[A](maybe: Maybe[A]): Option[A] = maybe.asOption

  implicit def fromOption[A](option: Option[A]): Maybe[A] =
    option match {
      case Some(value) => Just(value)
      case None        => Nothing
    }

  implicit def fromTry[A](aTry: Try[A]): Maybe[A] = aTry match {
    case Success(value) => Just(value)
    case Failure(_)     => Nothing
  }

  /** An implicit conversion that converts an option to an iterable value */
  implicit def maybe2Iterable[A](xo: Maybe[A]): Iterable[A] =
    MaybeLike.maybe2Iterable(xo)
}
