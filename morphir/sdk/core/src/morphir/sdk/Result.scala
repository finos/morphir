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

import morphir.sdk.Maybe._

sealed abstract class Result[+E, +A] extends Product with Serializable { self =>

  def isOk: Boolean

  def isErr: Boolean

  def flatMap[A1, E1 >: E](fn: A => Result[E1, A1]): Result[E1, A1] =
    this match {
      case Result.Ok(value) => fn(value)
      case _                => this.asInstanceOf[Result[E, A1]]
    }

  def getOrElse[A1 >: A](fallbackValue: A1): A1
  @inline def withDefault[A1 >: A](fallbackValue: A1): A1 = getOrElse(fallbackValue)

  def map[A1](fn: A => A1): Result[E, A1] =
    this match {
      case Result.Ok(value) => Result.Ok(fn(value))
      case _                => this.asInstanceOf[Result[E, A1]]
    }

  def mapError[E1 >: E](fn: E => E1): Result[E1, A]

  def toOption: Option[A] = self match {
    case Result.Ok(value) => Option(value)
    case Result.Err(_)    => None
  }

  def toMaybe: Maybe[A] =
    self match {
      case Result.Ok(value) => Maybe.just(value)
      case _                => Maybe.nothing
    }

}

object Result {

  type Result[+E, +A] = morphir.sdk.Result[E, A]

  case class Ok[+E, +A](value: A) extends Result[E, A] {

    def isOk: Boolean = true

    def isErr: Boolean = false

    def getOrElse[A1 >: A](fallbackValue: A1): A1 = value

    def mapError[E1 >: E](fn: E => E1): Result[E1, A] =
      this.asInstanceOf[Result[E1, A]]

    def withErr[E1 >: E]: Result[E1, A] = this
  }

  case class Err[+E, +A](error: E) extends Result[E, A] {

    def isOk: Boolean = false

    def isErr: Boolean = true

    def getOrElse[A1 >: A](fallbackValue: A1): A1 = fallbackValue

    def mapError[E1 >: E](fn: E => E1): Result[E1, A] =
      Err(fn(error))

    def withOk[A1 >: A]: Result[E, A1] = this
  }

  def ok[A](value: A): Result[Nothing, A] = Ok(value)

  def err[E](error: E): Result[E, Nothing] = Err(error)

  def andThen[E, A, B](fn: A => Result[E, B])(result: Result[E, A]): Result[E, B] =
    result.flatMap(fn)

  def map[X, A, V](fn: A => V)(result: Result[X, A]): Result[X, V] =
    result.map(fn)

  def map2[X, A, B, V](fn: (A, B) => V)(resA: Result[X, A])(resB: Result[X, B]): Result[X, V] =
    (resA, resB) match {
      case (Ok(a), Ok(b))    => Ok(fn(a, b))
      case (err @ Err(_), _) => err.asInstanceOf[Result[X, V]]
      case (_, err @ Err(_)) => err.asInstanceOf[Result[X, V]]
    }

  def map3[X, A, B, C, V](
    fn: (A, B, C) => V
  )(resA: Result[X, A])(resB: Result[X, B])(resC: Result[X, C]): Result[X, V] =
    (resA, resB, resC) match {
      case (Ok(a), Ok(b), Ok(c)) => Ok(fn(a, b, c))
      case (err @ Err(_), _, _)  => err.asInstanceOf[Result[X, V]]
      case (_, err @ Err(_), _)  => err.asInstanceOf[Result[X, V]]
      case (_, _, err @ Err(_))  => err.asInstanceOf[Result[X, V]]
    }

  def map4[X, A, B, C, D, V](
    fn: (A, B, C, D) => V
  )(resA: Result[X, A])(resB: Result[X, B])(resC: Result[X, C])(resD: Result[X, D]): Result[X, V] =
    (resA, resB, resC, resD) match {
      case (Ok(a), Ok(b), Ok(c), Ok(d)) => Ok(fn(a, b, c, d))
      case (err @ Err(_), _, _, _)      => err.asInstanceOf[Result[X, V]]
      case (_, err @ Err(_), _, _)      => err.asInstanceOf[Result[X, V]]
      case (_, _, err @ Err(_), _)      => err.asInstanceOf[Result[X, V]]
      case (_, _, _, err @ Err(_))      => err.asInstanceOf[Result[X, V]]
    }

  def map5[X, A, B, C, D, E, V](
    fn: (A, B, C, D, E) => V
  )(resA: Result[X, A])(resB: Result[X, B])(resC: Result[X, C])(resD: Result[X, D])(resE: Result[X, E]): Result[X, V] =
    (resA, resB, resC, resD, resE) match {
      case (Ok(a), Ok(b), Ok(c), Ok(d), Ok(e)) => Ok(fn(a, b, c, d, e))
      case (err @ Err(_), _, _, _, _)          => err.asInstanceOf[Result[X, V]]
      case (_, err @ Err(_), _, _, _)          => err.asInstanceOf[Result[X, V]]
      case (_, _, err @ Err(_), _, _)          => err.asInstanceOf[Result[X, V]]
      case (_, _, _, err @ Err(_), _)          => err.asInstanceOf[Result[X, V]]
      case (_, _, _, _, err @ Err(_))          => err.asInstanceOf[Result[X, V]]
    }

  def mapError[E, E1, A](fn: E => E1): Result[E, A] => Result[E1, A] = {
    case Err(error) => Err(fn(error))
    case result     => result.asInstanceOf[Result[E1, A]]
  }

  def toMaybe[E, A](result: Result[E, A]): Maybe[A] =
    result match {
      case Ok(value) => Maybe.just(value)
      case _         => Maybe.nothing
    }

  def fromMaybe[E, A](errorValue: => E): Maybe[A] => Result[E, A] = {
    case Maybe.Just(value) => Result.Ok(value)
    case Maybe.Nothing     => Result.Err(errorValue)
  }

  def fromOption[E, A](errorValue: => E): Option[A] => Result[E, A] = {
    case Some(value) => Result.Ok(value)
    case None        => Result.Err(errorValue)
  }

  def fromEither[E, A](either: Either[E, A]): Result[E, A] =
    either match {
      case Left(err)    => Result.Err(err)
      case Right(value) => Result.Ok(value)
    }

  implicit def resultFromEither[E, A](either: Either[E, A]): Result[E, A] =
    either match {
      case Left(err)    => Result.Err(err)
      case Right(value) => Result.Ok(value)
    }

  def unit[E]: Result[E, Unit] = Result.Ok(())
}
