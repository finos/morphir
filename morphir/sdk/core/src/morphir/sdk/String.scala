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

import morphir.sdk.Char.Char
import morphir.sdk.Maybe.Maybe

object String {
  type String = scala.Predef.String

  @inline def isEmpty(str: String): Basics.Bool = str.isEmpty()

  @inline def length(str: String): Basics.Int = str.length()

  @inline def reverse(str: String): String = str.reverse

  def repeat(times: Basics.Int, str: String): String =
    Array.fill[String](times.toInt)(str).mkString

  @inline def replace(
    literal: String,
    replacement: String,
    target: String
  ): String =
    target.replace(literal, replacement)

  @inline def fromInt(int: Basics.Int): String =
    int.toString

  @inline def append(first: String)(second: String): String = first + second

  @inline def ++(first: String, second: String): String = first + second

  @inline def concat(strings: List[String]): String = strings.mkString

  @inline def split(sep: String)(target: String): List[String] =
    target.split(sep).toList // TODO: These aren't exactly the same

  def toInt(text: String): Maybe[Basics.Int] =
    try Maybe.just(text.toInt)
    catch {
      case _: NumberFormatException => Maybe.nothing
    }

  @inline def toUpper(text: String): String =
    text.toUpperCase()

  @inline def toLower(text: String): String =
    text.toLowerCase()

  @inline def trim(text: String): String = text.trim()

  /** Put many strings together with a given separator.
    */
  def join(sep: Char)(chunks: List[String]): String =
    chunks.mkString(sep.toString())

  /** Put many strings together with a given separator.
    */
  def join(sep: String)(chunks: List[String]): String =
    chunks.mkString(sep)

  def words(str: String): List[String] = str.split("\\s").toList

  def lines(str: String): List[String] = str.split("\\n").toList

  def slice(start: Basics.Int)(end: Basics.Int)(str: String): String =
    str.substring(start.toInt, end.toInt)

  def left(n: Basics.Int)(str: String): String = str.substring(0, n.toInt)

  def right(n: Basics.Int)(str: String): String =
    str.slice(str.length - n.toInt, str.length)

  def dropLeft(n: Basics.Int)(str: String): String = str.drop(n.toInt)

  def dropRight(n: Basics.Int)(str: String): String = str.dropRight(n.toInt)

  def contains(substring: String)(str: String): Basics.Bool = str.contains(substring)

  def startsWith(substring: String)(str: String): Basics.Bool =
    str.startsWith(substring)

  def endsWith(substring: String)(str: String): Basics.Bool = str.endsWith(substring)

  def indexes(substring: String)(str: String): List[Basics.Int] =
    str.r.findAllMatchIn(substring).map(_.start).toList

  def indices(substring: String)(str: String): List[Basics.Int] =
    indexes(substring)(str)

  def toFloat(str: String): Maybe[morphir.sdk.Float.Float] =
    try Maybe.just(str.toDouble)
    catch {
      case _: NumberFormatException => Maybe.nothing
    }

  def fromFloat(float: morphir.sdk.Float.Float): String = float.toString
  def fromFloat(float: scala.Float): String             = float.toString

  def fromChar(ch: Char): String = ch.toString

  def cons(ch: Char)(str: String): String = s"$ch$str"

  def uncons(str: String): Maybe[(Char, String)] =
    str match {
      case a if a.length == 0 => Maybe.nothing
      case a if a.length == 1 => Maybe.just((Char.from(a.charAt(0)), ""))
      case _ =>
        Maybe.just((Char.from(str.charAt(0)), str.substring(1, str.length)))
    }

  def toList(str: String): List[Char] = str.toList.map(Char.from)

  def fromList(chList: List[Char]): String = chList.mkString

  def pad(n: Basics.Int)(ch: Char)(str: String): String = {
    val padding: String = ch.toString * n.toInt
    padding + str + padding
  }

  def padLeft(n: Basics.Int)(ch: Char)(str: String): String =
    (ch.toString * n.toInt) + str

  def padRight(n: Basics.Int)(ch: Char)(str: String): String =
    str + (ch.toString * n.toInt)

  def trimLeft(str: String): String = str.replaceAll("^\\s+", "")

  def trimRight(str: String): String = str.replaceAll("\\s+$", "")

  def map(f: Char => Char)(str: String): String =
    str.toList.map(ch => f(Char.from(ch))).mkString

  def filter(f: Char => Basics.Bool)(str: String): String =
    str.toList.filter(ch => f(Char.from(ch))).mkString

  def foldl[B](f: Char => B => B)(z: B)(str: String): B =
    str.toList.foldLeft(z)((soFar, next) => f(Char.from(next))(soFar))

  def foldr[B](f: Char => B => B)(z: B)(str: String): B =
    str.toList.foldRight(z)((next, soFar) => f(Char.from(next))(soFar))

  def any(f: (Char => Basics.Bool))(str: String): Basics.Bool =
    str.toList.exists(ch => f(Char.from(ch)))

  def all(f: (Char => Basics.Bool))(str: String): Basics.Bool =
    str.toList.forall(ch => f(Char.from(ch)))

  implicit class StringOps(private val self: String) extends AnyVal {
    def ++(that: String): String = self + that
  }
}
