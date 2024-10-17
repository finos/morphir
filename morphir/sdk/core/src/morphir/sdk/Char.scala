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

//TODO: We need to think how we want to represent chars as Elm chars support full unicode
//    : but java cannot store full unicode in a single char
object Char {
  sealed abstract class Char {}

  private case class UnicodeChar(codePoint: Int) extends Char {
    override def toString: String = new String(Character.toChars(codePoint))
  }

  def isAlpha(ch: Char): Boolean =
    isLower(ch) || isUpper(ch)

  def isAlphaNum(ch: Char): Boolean =
    isLower(ch) || isUpper(ch) || isDigit(ch)

  /** Detect upper case ASCII characters.
    *
    * @param ch
    *   a character
    * @return
    */
  def isUpper(ch: Char): Boolean = ch match {
    case UnicodeChar(code) => code <= 0x5a && 0x41 <= code
  }

  def isLower(ch: Char): Boolean = ch match {
    case UnicodeChar(code) => 0x61 <= code && code <= 0x7a
  }

  def isDigit(ch: Char): Boolean = ch match {
    case UnicodeChar(code) => code <= 0x39 && 0x30 <= code
  }

  /** Detect octal digits `01234567`
    *
    * @param ch
    * @return
    */
  def isOctDigit(ch: Char): Boolean = ch match {
    case UnicodeChar(code) => code <= 0x37 && 0x30 <= code
  }

  def isHexDigit(ch: Char): Boolean = ch match {
    case UnicodeChar(code) =>
      (0x30 <= code && code <= 0x39) || (0x41 <= code && code <= 0x46) || (0x61 <= code && code <= 0x66)
  }

  def toUpper(ch: scala.Char): Char = Char.from(ch.toUpper)

  def toUpper(ch: Char): Char = ch match {
    case UnicodeChar(codePoint) => UnicodeChar(Character.toUpperCase(codePoint))
  }

  def toLower(ch: scala.Char): Char = Char.from(ch.toLower)

  def toLower(ch: Char): Char = ch match {
    case UnicodeChar(codePoint) => UnicodeChar(Character.toLowerCase(codePoint))
  }

  def toCode(ch: Char): Int = ch match {
    case UnicodeChar(codePoint) => codePoint
  }

  def fromCode(codePoint: Int): Char =
    UnicodeChar(codePoint)

  def from(ch: scala.Char): Char = UnicodeChar(ch.toInt)
  def from(ch: Int): Char        = UnicodeChar(ch)

}
