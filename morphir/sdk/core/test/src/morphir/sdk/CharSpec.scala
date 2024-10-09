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

import zio.test.Assertion._
import zio.test._
import morphir.testing.MorphirBaseSpec
object CharSpec extends MorphirBaseSpec {
  def spec = suite("CharSpec")(
    suite("Char.toCode specs")(
      toCodeTests(
        Char.from('A')     -> 65,
        Char.from('B')     -> 66,
        Char.from(0x1f603) -> 0x1f603,
        Char.from(120506)  -> 0x1d6ba
      ): _*
    ),
    suite("Char.isUpper specs")(
      isUpperTests(
        Char.from('A')     -> true,
        Char.from('B')     -> true,
        Char.from('Z')     -> true,
        Char.from('0')     -> false,
        Char.from('a')     -> false,
        Char.from('-')     -> false,
        Char.from(0x1d6ba) -> false
      ): _*
    ),
    suite("Char.isLower specs")(
      isLowerTests(
        Char.from('a') -> true,
        Char.from('b') -> true,
        Char.from('z') -> true,
        Char.from('0') -> false,
        Char.from('A') -> false,
        Char.from('-') -> false,
        // Testing π - which is an uppercase unicode character
        Char.from(0x1d6b7) -> false
      ): _*
    ),
    suite("Char.isAlpha specs")(
      isAlphaTests(
        Char.from('a') -> true,
        Char.from('b') -> true,
        Char.from('E') -> true,
        Char.from('Y') -> true,
        Char.from('0') -> false,
        Char.from('-') -> false,
        // Testing π - which is an uppercase unicode character
        Char.from(0x1d6b7) -> false
      ): _*
    ),
    suite("Char.isAlphaNum specs")(
      isAlphaNumTests(
        Char.from('a') -> true,
        Char.from('b') -> true,
        Char.from('E') -> true,
        Char.from('Y') -> true,
        Char.from('0') -> true,
        Char.from('7') -> true,
        Char.from('9') -> true,
        Char.from('-') -> false,
        // Testing π - which is an uppercase unicode character
        Char.from(0x1d6b7) -> false,
        Char.from(0x1d6ba) -> false
      ): _*
    ),
    suite("Char.isDigit specs")(
      isDigitTests(
        Char.from('0') -> true,
        Char.from('1') -> true,
        Char.from('9') -> true,
        Char.from('a') -> false,
        Char.from('b') -> false,
        Char.from('A') -> false,
        // Testing π - which is an uppercase unicode character
        Char.from(0x1d6b7) -> false
      ): _*
    ),
    suite("Char.isOctDigit specs")(
      isOctDigitTests(
        Char.from('0') -> true,
        Char.from('1') -> true,
        Char.from('7') -> true,
        Char.from('8') -> false,
        Char.from('a') -> false,
        Char.from('A') -> false,
        // Testing π - which is an uppercase unicode character
        Char.from(0x1d6b7) -> false
      ): _*
    ),
    suite("Char.isHexDigit specs")(
      test(
        s"Given a character calliing isHexDigit should return true only for hex digits"
      ) {
        check(Gen.unicodeChar) { input =>
          val sut      = Char.from(input)
          val expected = "0123456789abcdefABCDEF".contains(input)
          assert(Char.isHexDigit(sut))(equalTo(expected))
        }

      }
    )
  )

  def toCodeTests(cases: (Char.Char, Int)*) =
    cases.map { case (input, expectedCode) =>
      test(
        s"Given a Char: '$input' calliing toCode should return '$expectedCode'"
      ) {
        assert(Char.toCode(input))(equalTo(expectedCode))
      }
    }

  def isUpperTests(cases: (Char.Char, Boolean)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a Char: '$input' calliing isUpper should return '$expected'"
      ) {
        assert(Char.isUpper(input))(equalTo(expected))
      }
    }

  def isLowerTests(cases: (Char.Char, Boolean)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a Char: '$input' calliing isLower should return '$expected'"
      ) {
        assert(Char.isLower(input))(equalTo(expected))
      }
    }

  def isAlphaTests(cases: (Char.Char, Boolean)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a Char: '$input' calliing isAlpha should return '$expected'"
      ) {
        assert(Char.isAlpha(input))(equalTo(expected))
      }
    }

  def isAlphaNumTests(cases: (Char.Char, Boolean)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a Char: '$input' calliing isAlphaNum should return '$expected'"
      ) {
        assert(Char.isAlphaNum(input))(equalTo(expected))
      }
    }

  def isDigitTests(cases: (Char.Char, Boolean)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a Char: '$input' calliing isDigit should return '$expected'"
      ) {
        assert(Char.isDigit(input))(equalTo(expected))
      }
    }

  def isOctDigitTests(cases: (Char.Char, Boolean)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a Char: '$input' calliing isOctDigit should return '$expected'"
      ) {
        assert(Char.isOctDigit(input))(equalTo(expected))
      }
    }
}
