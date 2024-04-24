package morphir.std.result
import scala.util.{Failure, Success, Try}

enum Result[+E, +A]:
  self =>
  case Err(err: E)
  case Ok(value: A)

  def fold[B](onError: E => B, onSuccess: A => B): B = self match
    case Err(err) => onError(err)
    case Ok(ok)   => onSuccess(ok)

  def isError: Boolean = self match
    case Err(_) => true
    case _      => false

  def isErrorAnd(f: E => Boolean): Boolean = self match
    case Err(err) => f(err)
    case _        => false

  def isOk: Boolean = self match
    case Ok(_) => true
    case _     => false

  def isOkAnd(f: A => Boolean): Boolean = self match
    case Ok(ok) => f(ok)
    case _      => false

  def map[B](f: A => B): Result[E, B] = self match
    case Err(err) => Err(err)
    case Ok(ok)   => Ok(f(ok))

  def mappError[E1](f: E => E1): Result[E1, A] = self match
    case Err(err) => Err(f(err))
    case Ok(ok)   => Ok(ok)

  def contains[B >: A](elem: B): Boolean = exists(_ == elem)

  def exists(p: A => Boolean): Boolean = self match
    case Ok(ok) => p(ok)
    case _      => false

  def expect(message: String): A = self match
    case Ok(ok) => ok
    case _      => throw new Panic(message)

  def flatMap[E1 >: E, A1](
      f: A => Result[E1, A1]
  ): Result[E1, A1] = self match
    case Err(err) => Err(err)
    case Ok(ok)   => f(ok)

  def flatten[E1 >: E, A1](using
      ev: A <:< Result[E1, A1]
  ): Result[E1, A1] = self match
    case Err(err) => Err(err)
    case Ok(ok)   => ok

  def forall(p: A => Boolean): Boolean = self match
    case Ok(ok) => p(ok)
    case _      => true

  def foreach[U](f: A => U): Unit = self match
    case Ok(ok) => f(ok)
    case _      => ()

  def getOrElse[A1 >: A](default: A1): A1 = self match
    case Ok(ok) => ok
    case _      => default

  def orElse[E1, A1 >: A](default: => Result[E1, A1]): Result[E1, A1] =
    self match
      case Ok(ok) => Ok(ok)
      case _      => default

  def toEither: Either[E, A] = self match
    case Err(err) => Left(err)
    case Ok(ok)   => Right(ok)

  def toOption: Option[A] = self match
    case Err(_) => None
    case Ok(ok) => Some(ok)

  def toTry(using ev: E <:< Throwable): Try[A] = self match
    case Err(err) => Failure(err)
    case Ok(ok)   => Success(ok)

  def toIterator: Iterator[A] = self match
    case Ok(ok) => Iterator.single(ok)
    case _      => Iterator.empty

  def toSeq: Seq[A] = self match
    case Ok(ok) => Seq(ok)
    case _      => Seq.empty

  def toList: List[A] = self match
    case Ok(ok) => List(ok)
    case _      => List.empty

  def toVector: Vector[A] = self match
    case Ok(ok) => Vector(ok)
    case _      => Vector.empty

end Result

object Result:
  def ok[A](value: A): Result[Nothing, A] = Result.Ok(value)
  def err[E](err: E): Result[E, Nothing] = Result.Err(err)
  def fail[E](err: E): Result[E, Nothing] = Result.Err(err)

  def fromEither[E, A](either: Either[E, A]): Result[E, A] = either match
    case Left(err) => Result.Err(err)
    case Right(ok) => Result.Ok(ok)

  def fromOption[A](opt: Option[A]): Result[Unit, A] = opt match
    case Some(value) => Result.Ok(value)
    case None        => Result.Err(())

  def fromTry[A](input: Try[A]): Result[Throwable, A] = input match
    case Failure(err) => Result.Err(err)
    case Success(ok)  => Result.Ok(ok)

  given [A]: Conversion[Result[_, A], Option[A]] = _.toOption
  given [Err, A]: Conversion[Result[Err, A], Either[Err, A]] = _.toEither
  given [Err, A]: Conversion[Either[Err, A], Result[Err, A]] = fromEither(_)

end Result

case class Panic(message: String) extends RuntimeException(message)
