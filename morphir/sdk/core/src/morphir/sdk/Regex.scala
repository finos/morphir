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

import morphir.sdk.Maybe.Maybe

import scala.util.Try
import scala.util.matching.{ Regex => RE }

object Regex {

  case class Regex(toRE: RE) extends AnyVal
  case class Options(caseInsensitive: Boolean, multiline: Boolean)
  case class Match(
    _match: String,
    index: Int,
    number: Int,
    submatches: List[Maybe[String]]
  )

  val never: Regex = Regex(".^".r)

  def fromString(string: String): Maybe[Regex] =
    Try(string.r).toOption.map(Regex.apply)

  def split(regex: Regex)(string: String): List[String] =
    regex.toRE.split(string).toList

  /** Find matches in a string:
    *
    * val location: Regex = Maybe.withDefault(never)(fromString "[oi]n a (\\w+)")
    *
    * val places : List[Match places = find location "I am on a boat in a lake."
    *
    * // places.map(_.match) == List( "on a boat", "in a lake" ) // places.map(_.submatches) == List( List(Just "boat"),
    * List(Just "lake") )
    *
    * > Note: .submatches will always return an empty list
    */
  def find(regex: Regex)(str: String): List[Match] =
    regex.toRE.findAllMatchIn(str).toList.zipWithIndex.map { case (mtch, idx) =>
      Match(
        _match = mtch.matched,
        index = mtch.start,
        number = idx + 1,
        submatches = mtch.subgroups.map(Maybe.Just(_))
      )
    }

}
